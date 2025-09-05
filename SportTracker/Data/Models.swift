import Foundation
import SwiftData

// MARK: - Enums

enum UnitSystem: String, Codable, CaseIterable {
    case metric, imperial
}

enum MuscleGroup: Int, Codable, CaseIterable {
    case chestBack = 1
    case arms = 2
    case legs = 3
    case core = 4
}

enum SyncState: Int, Codable {
    case localOnly = 0
    case pending
    case synced
    case conflict
}

// MARK: - Settings & User

@Model
final class UserProfile {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String? = nil
    var unitSystem: UnitSystem = UnitSystem.metric

    init(id: UUID = UUID(), displayName: String? = nil, unitSystem: UnitSystem = UnitSystem.metric) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.displayName = displayName
        self.unitSystem = unitSystem
    }
}

@Model
final class Settings {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    // Scoring factors (defaults)
    var runningDistanceFactor: Double = 10.0
    var runningTimeFactor: Double = 0.5
    var runningPaceBaselineSecPerKm: Double = 360
    var runningPaceFactor: Double = 50.0

    var gymRepsFactor: Double = 1.0
    var gymWeightedFactor: Double = 0.1

    var prefersMiles: Bool = false
    var prefersPounds: Bool = false

    init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Exercise Library

@Model
final class Exercise {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var name: String = ""
    var muscleGroup: MuscleGroup = MuscleGroup.chestBack
    var isWeighted: Bool = false
    var exerciseDescription: String? = nil
    var iconSystemName: String? = nil
    var imageData: Data? = nil
    var isCustom: Bool = true
    var notes: String = ""

    // Inversa hacia el campo persistido opcional del set (_exercise)
    @Relationship(deleteRule: .nullify, inverse: \StrengthSet._exercise)
    var usedInSets: [StrengthSet]? = nil

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup,
        isWeighted: Bool,
        exerciseDescription: String? = nil,
        iconSystemName: String? = nil,
        imageData: Data? = nil,
        isCustom: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.name = name
        self.muscleGroup = muscleGroup
        self.isWeighted = isWeighted
        self.exerciseDescription = exerciseDescription
        self.iconSystemName = iconSystemName
        self.imageData = imageData
        self.isCustom = isCustom
        self.notes = notes
    }
}

// MARK: - Strength (Gym)

@Model
final class StrengthSet {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Inversa al campo persistido de la sesión (_sets)
    @Relationship(deleteRule: .nullify, inverse: \StrengthSession._sets)
    var session: StrengthSession? = nil

    // ⚙️ Persistido (opcional) para cumplir CloudKit
    @Relationship(deleteRule: .noAction)
    var _exercise: Exercise? = nil

    // 👁️ Público (compatibilidad con el resto del código)
    //  - Antes hacía force-unwrap y crasheaba si _exercise era nil en datos antiguos.
    //  - Ahora: si falta, creamos un Exercise “placeholder” y lo asignamos para curar el dato.
    @Transient
    var exercise: Exercise {
        get {
            if let ex = _exercise { return ex }
            // Auto-heal para registros antiguos sin exercise
            let placeholder = Exercise(
                name: "(missing exercise)",
                muscleGroup: MuscleGroup.arms,
                isWeighted: false,
                exerciseDescription: "Auto-repaired placeholder",
                iconSystemName: nil,
                imageData: nil,
                isCustom: true,
                notes: ""
            )
            _exercise = placeholder
            return placeholder
        }
        set { _exercise = newValue }
    }

    var order: Int = 0
    var reps: Int = 0
    var weightKg: Double? = nil
    var restSeconds: Int? = nil

    init(
        id: UUID = UUID(),
        exercise: Exercise,
        order: Int,
        reps: Int,
        weightKg: Double? = nil,
        restSeconds: Int? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self._exercise = exercise
        self.order = order
        self.reps = reps
        self.weightKg = weightKg
        self.restSeconds = restSeconds
    }
}

@Model
final class StrengthSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var date: Date = Date()
    var durationSeconds: Int? = nil
    var notes: String? = nil

    // ⚙️ Persistido (opcional) para CloudKit
    @Relationship(deleteRule: .cascade)
    var _sets: [StrengthSet]? = nil

    // 👁️ Público no opcional (compatibilidad con Views/lógica)
    @Transient
    var sets: [StrengthSet] {
        get { _sets ?? [] }
        set { _sets = newValue }
    }

    var totalPoints: Double = 0

    init(id: UUID = UUID(), date: Date = Date(), durationSeconds: Int? = nil, notes: String? = nil) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.date = date
        self.durationSeconds = durationSeconds
        self.notes = notes
    }
}

// MARK: - Running

@Model
final class RunningSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var remoteId: String? = nil

    var date: Date = Date()
    var durationSeconds: Int = 0
    var distanceMeters: Double = 0
    var notes: String? = nil

    var routePolyline: String? = nil
    var totalPoints: Double = 0

    // Inversa con RunningWatchDetail.session
    @Relationship(deleteRule: .nullify, inverse: \RunningWatchDetail.session)
    var watchDetail: RunningWatchDetail? = nil

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSeconds: Int,
        distanceMeters: Double,
        notes: String? = nil,
        routePolyline: String? = nil,
        remoteId: String? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.date = date
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.notes = notes
        self.routePolyline = routePolyline
        self.remoteId = remoteId
    }

    var paceSecondsPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        let km = distanceMeters / 1000.0
        return Double(durationSeconds) / km
    }

    var distanceKm: Double { distanceMeters / 1000.0 }
}

// MARK: - Goals

@Model
final class RunningGoal {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var weeklyKilometers: Double = 0

    init(id: UUID = UUID(), weeklyKilometers: Double = 0) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.weeklyKilometers = weeklyKilometers
    }
}

@Model
final class GymGoal {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var targetChestBack: Int = 0
    var targetArms: Int = 0
    var targetLegs: Int = 0
    var targetCore: Int = 0

    init(
        id: UUID = UUID(),
        targetChestBack: Int = 0,
        targetArms: Int = 0,
        targetLegs: Int = 0,
        targetCore: Int = 0
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.targetChestBack = targetChestBack
        self.targetArms = targetArms
        self.targetLegs = targetLegs
        self.targetCore = targetCore
    }

    var totalWeeklyTarget: Int {
        targetChestBack + targetArms + targetLegs + targetCore
    }
}

// MARK: - Watch Running Detail

@Model
final class RunningWatchDetail {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify)
    var session: RunningSession? = nil

    // ⚙️ Persistidos (opcionales) para CloudKit
    @Relationship(deleteRule: .cascade, inverse: \WatchHRPoint.detail)
    var _hrPoints: [WatchHRPoint]? = nil

    @Relationship(deleteRule: .cascade, inverse: \WatchPacePoint.detail)
    var _pacePoints: [WatchPacePoint]? = nil

    @Relationship(deleteRule: .cascade, inverse: \WatchElevationPoint.detail)
    var _elevationPoints: [WatchElevationPoint]? = nil

    @Relationship(deleteRule: .cascade, inverse: \RunningWatchSplit.detail)
    var _splits: [RunningWatchSplit]? = nil

    // 👁️ Públicas no opcionales
    @Transient var hrPoints: [WatchHRPoint] {
        get { _hrPoints ?? [] }
        set { _hrPoints = newValue }
    }
    @Transient var pacePoints: [WatchPacePoint] {
        get { _pacePoints ?? [] }
        set { _pacePoints = newValue }
    }
    @Transient var elevationPoints: [WatchElevationPoint] {
        get { _elevationPoints ?? [] }
        set { _elevationPoints = newValue }
    }
    @Transient var splits: [RunningWatchSplit] {
        get { _splits ?? [] }
        set { _splits = newValue }
    }

    var routePolyline: String? = nil

    init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class WatchHRPoint {
    var id: UUID = UUID()
    var t: Double = 0
    var v: Double = 0
    @Relationship(deleteRule: .nullify) var detail: RunningWatchDetail? = nil

    init(id: UUID = UUID(), t: Double, v: Double) {
        self.id = id; self.t = t; self.v = v
    }
}

@Model
final class WatchPacePoint {
    var id: UUID = UUID()
    var t: Double = 0
    var v: Double = 0
    @Relationship(deleteRule: .nullify) var detail: RunningWatchDetail? = nil

    init(id: UUID = UUID(), t: Double, v: Double) {
        self.id = id; self.t = t; self.v = v
    }
}

@Model
final class WatchElevationPoint {
    var id: UUID = UUID()
    var t: Double = 0
    var v: Double = 0
    @Relationship(deleteRule: .nullify) var detail: RunningWatchDetail? = nil

    init(id: UUID = UUID(), t: Double, v: Double) {
        self.id = id; self.t = t; self.v = v
    }
}

@Model
final class RunningWatchSplit {
    var id: UUID = UUID()
    var index: Int = 0
    var startOffset: Double = 0
    var endOffset: Double = 0
    var duration: Double = 0
    var distanceMeters: Double = 0
    var avgHR: Double? = nil
    var avgSpeed: Double? = nil
    @Relationship(deleteRule: .nullify) var detail: RunningWatchDetail? = nil

    init(
        id: UUID = UUID(),
        index: Int,
        startOffset: Double,
        endOffset: Double,
        duration: Double,
        distanceMeters: Double,
        avgHR: Double?,
        avgSpeed: Double?
    ) {
        self.id = id
        self.index = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.avgHR = avgHR
        self.avgSpeed = avgSpeed
    }
}
