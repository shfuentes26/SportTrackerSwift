import Foundation
import SwiftData

// MARK: - Enums
enum UnitSystem: String, Codable, CaseIterable { case metric, imperial }
enum MuscleGroup: Int, Codable, CaseIterable { case chestBack = 1, arms = 2, legs = 3, core = 4 }
enum SyncState: Int, Codable { case localOnly = 0, pending, synced, conflict }

// =========================
// USER / SETTINGS
// =========================

@Model
final class STUserProfile {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String? = nil

    var unitSystemRaw: String = UnitSystem.metric.rawValue
    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
        set { unitSystemRaw = newValue.rawValue }
    }

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    init() {}
}


@Model
final class UserProfile {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String? = nil

    // Raw + computed (mismo layout que STUserProfile)
    var unitSystemRaw: String = UnitSystem.metric.rawValue
    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
        set { unitSystemRaw = newValue.rawValue }
    }

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    init() {}
}

@Model
final class Settings {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    var remoteId: String? = nil

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    // Scoring factors
    var runningDistanceFactor: Double = 10.0
    var runningTimeFactor: Double = 0.5
    var runningPaceBaselineSecPerKm: Double = 360
    var runningPaceFactor: Double = 50.0
    var gymRepsFactor: Double = 1.0
    var gymWeightedFactor: Double = 0.1

    var prefersMiles: Bool = false
    var prefersPounds: Bool = false

    init() {}
}

// =========================
// EXERCISE LIBRARY
// =========================

@Model
final class Exercise {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    var remoteId: String? = nil

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    var name: String = ""
    var muscleGroupRaw: Int = MuscleGroup.arms.rawValue
    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .arms }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var isWeighted: Bool = false
    var exerciseDescription: String? = nil
    var iconSystemName: String? = nil
    var imageData: Data? = nil
    var isCustom: Bool = true
    var notes: String = ""

    // Inversa (opcional) para StrengthSet.exercise
    var sets: [StrengthSet]? = nil

    init() {}
    
    convenience init(
        name: String,
        muscleGroup: MuscleGroup,
        isWeighted: Bool,
        exerciseDescription: String? = nil,
        iconSystemName: String? = nil,
        imageData: Data? = nil,
        isCustom: Bool = true,
        notes: String = ""
    ) {
        self.init()
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.isWeighted = isWeighted
        self.exerciseDescription = exerciseDescription
        self.iconSystemName = iconSystemName
        self.imageData = imageData
        self.isCustom = isCustom
        self.notes = notes
    }
}

// =========================
// STRENGTH
// =========================

@Model
final class StrengthSet {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    var remoteId: String? = nil

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    // Relaciones
    var session: StrengthSession? = nil
    // CloudKit: la relación debe ser opcional
    var exercise: Exercise? = nil

    // Atributos
    var order: Int = 0
    var reps: Int = 0
    var weightKg: Double? = nil
    var restSeconds: Int? = nil

    init(exercise: Exercise? = nil) { self.exercise = exercise }
    
    // Mantengo un init de conveniencia con Exercise no opcional para no romper llamadas actuales
    convenience init(
        exercise: Exercise,
        order: Int,
        reps: Int,
        weightKg: Double? = nil,
        restSeconds: Int? = nil
    ) {
        self.init(exercise: exercise)
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
    var deletedAt: Date? = nil
    var remoteId: String? = nil

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    var date: Date = Date()
    var durationSeconds: Int? = nil
    var notes: String? = nil

    // CloudKit: relación to-many opcional
    var sets: [StrengthSet]? = nil

    var totalPoints: Double = 0

    init() {}
    
    convenience init(date: Date, notes: String? = nil) {
        self.init()
        self.date = date
        self.notes = notes
    }
}

// =========================
// RUNNING
// =========================

@Model
final class RunningSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    var remoteId: String? = nil

    var syncStateRaw: Int = SyncState.localOnly.rawValue
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    var date: Date = Date()
    var durationSeconds: Int = 0
    var distanceMeters: Double = 0
    var notes: String? = nil
    var routePolyline: String? = nil
    var totalPoints: Double = 0
    
    var detail: RunningWatchDetail? = nil

    var paceSecondsPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return Double(durationSeconds) / (distanceMeters / 1000.0)
    }
    var distanceKm: Double { distanceMeters / 1000.0 }

    init() {}
    
    convenience init(
        date: Date,
        durationSeconds: Int,
        distanceMeters: Double,
        notes: String? = nil,
        routePolyline: String? = nil
    ) {
        self.init()
        self.date = date
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.notes = notes
        self.routePolyline = routePolyline
    }
}

// =========================
// GOALS
// =========================

@Model
final class RunningGoal {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var weeklyKilometers: Double = 0

    init() {}
    
    convenience init(weeklyKilometers: Double) {
        self.init()
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

    var totalWeeklyTarget: Int { targetChestBack + targetArms + targetLegs + targetCore }

    init() {}
    
    convenience init(targetChestBack: Int, targetArms: Int, targetLegs: Int, targetCore: Int) {
        self.init()
        self.targetChestBack = targetChestBack
        self.targetArms = targetArms
        self.targetLegs = targetLegs
        self.targetCore = targetCore
    }
}

// =========================
// WATCH RUNNING DETAIL
// =========================

@Model
final class RunningWatchDetail {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var session: RunningSession? = nil
    // CloudKit: to-many opcionales
    var hrPoints: [WatchHRPoint]? = nil
    var pacePoints: [WatchPacePoint]? = nil
    var elevationPoints: [WatchElevationPoint]? = nil
    var splits: [RunningWatchSplit]? = nil
    var routePolyline: String? = nil

    init() {}
}

@Model
final class WatchHRPoint {
    var id: UUID = UUID()
    var t: Double = 0
    var v: Double = 0
    var detail: RunningWatchDetail? = nil

    init() {}
    
    convenience init(t: Double, v: Double, detail: RunningWatchDetail? = nil) {
        self.init()
        self.t = t
        self.v = v
        self.detail = detail
    }
}

@Model
final class WatchPacePoint {
    var id: UUID = UUID()
    var t: Double = 0
    var v: Double = 0
    var detail: RunningWatchDetail? = nil

    init() {}
    
    convenience init(t: Double, v: Double, detail: RunningWatchDetail? = nil) {
        self.init()
        self.t = t
        self.v = v
        self.detail = detail
    }
}

@Model
final class WatchElevationPoint {
    var id: UUID = UUID()
    var t: Double = 0
    var v: Double = 0
    var detail: RunningWatchDetail? = nil

    init() {}
    
    convenience init(t: Double, v: Double, detail: RunningWatchDetail? = nil) {
        self.init()
        self.t = t
        self.v = v
        self.detail = detail
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
    var detail: RunningWatchDetail? = nil

    init() {}
    
    convenience init(
        index: Int,
        startOffset: Double,
        endOffset: Double,
        duration: Double,
        distanceMeters: Double,
        avgHR: Double? = nil,
        avgSpeed: Double? = nil,
        detail: RunningWatchDetail? = nil
    ) {
        self.init()
        self.index = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.avgHR = avgHR
        self.avgSpeed = avgSpeed
        self.detail = detail
    }
}
