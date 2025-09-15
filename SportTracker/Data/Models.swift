//
//  Models.swift (fixed defaults for SwiftData)
//  SportTracker
//

import Foundation
import SwiftData

// MARK: - Enums

public enum UnitSystem: String, Codable, CaseIterable {
    case metric, imperial
}

public enum MuscleGroup: Int, Codable, CaseIterable {
    case chestBack = 1  // 1 Pecho/Espalda
    case arms = 2       // 2 Brazos
    case legs = 3       // 3 Piernas
    case core = 4       // 4 Core
}

public enum SyncState: Int, Codable {
    case localOnly = 0
    case pending
    case synced
    case conflict
}

// MARK: - Base protocol for sync metadata
public protocol SyncTracked {
    var id: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var remoteId: String? { get set }
    var syncState: SyncState { get set }
}

extension SyncTracked {
    public mutating func markUpdated() { updatedAt = Date() }
}

// MARK: - Settings & User

@Model
public final class UserProfile: SyncTracked {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date? = nil
    public var remoteId: String? = nil
    public var syncState: SyncState = SyncState.localOnly

    public var displayName: String?
    public var unitSystem: UnitSystem = UnitSystem.metric

    public init(id: UUID = UUID(), displayName: String? = nil, unitSystem: UnitSystem = UnitSystem.metric) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.displayName = displayName
        self.unitSystem = unitSystem
    }
}

@Model
public final class Settings: SyncTracked {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date? = nil
    public var remoteId: String? = nil
    //public var syncState: SyncState = SyncState.localOnly
    public var syncStateRaw: Int = SyncState.localOnly.rawValue
    
    public var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    // Scoring factors (tune in UI later)
    public var runningDistanceFactor: Double = 10.0       // pts per km
    public var runningTimeFactor: Double = 0.5            // pts per minute
    public var runningPaceBaselineSecPerKm: Double = 360  // 6:00 min/km baseline
    public var runningPaceFactor: Double = 50.0           // weight of pace score
    // NEW – superlinear distance boost
    public var runningEnduranceFactor: Double = 25.0      // magnitud del bonus
    public var runningEnduranceExponent: Double = 1.20    // >1 ⇒ crece más que lineal

    public var gymRepsFactor: Double = 1.0                // bodyweight: pts per rep
    public var gymWeightedFactor: Double = 0.1            // weighted: (kg * reps) * factor

    public init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    var prefersMiles: Bool = false     // false = km; true = miles
    var prefersPounds: Bool = false    // false = kg; true = lb
}

// MARK: - Exercise Library

@Model
public final class Exercise: SyncTracked {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date? = nil
    public var remoteId: String? = nil
    public var syncState: SyncState = SyncState.localOnly

    public var name: String
    public var muscleGroup: MuscleGroup
    public var isWeighted: Bool
    public var exerciseDescription: String?
    public var iconSystemName: String?   // SF Symbol name if any
    public var imageData: Data?          // Optional user photo/icon
    public var isCustom: Bool = true
    public var notes: String = ""

    public init(id: UUID = UUID(), name: String, muscleGroup: MuscleGroup, isWeighted: Bool, exerciseDescription: String? = nil, iconSystemName: String? = nil, imageData: Data? = nil, isCustom: Bool = true,notes: String = "") {
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

// MARK: - Strength (Gym) Sessions

@Model
public final class StrengthSet: SyncTracked {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date? = nil
    public var remoteId: String? = nil
    public var syncState: SyncState = SyncState.localOnly

    @Relationship(deleteRule: .nullify, inverse: \StrengthSession.sets)
    public var session: StrengthSession?

    @Relationship(deleteRule: .noAction)
    public var exercise: Exercise

    public var order: Int
    public var reps: Int
    public var weightKg: Double?  // nil for bodyweight
    public var restSeconds: Int?

    public init(id: UUID = UUID(), exercise: Exercise, order: Int, reps: Int, weightKg: Double? = nil, restSeconds: Int? = nil) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.exercise = exercise
        self.order = order
        self.reps = reps
        self.weightKg = weightKg
        self.restSeconds = restSeconds
    }
}

@Model
public final class StrengthSession: SyncTracked {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date? = nil
    public var remoteId: String? = nil
    public var syncState: SyncState = SyncState.localOnly

    public var date: Date
    public var durationSeconds: Int?
    public var notes: String?
    @Relationship(deleteRule: .cascade)
    public var sets: [StrengthSet] = []

    public var totalPoints: Double = 0

    public init(id: UUID = UUID(), date: Date = Date(), durationSeconds: Int? = nil, notes: String? = nil) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.date = date
        self.durationSeconds = durationSeconds
        self.notes = notes
    }
}

// MARK: - Running Sessions

@Model
public final class RunningSession: SyncTracked {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date? = nil
    public var remoteId: String? = nil
    public var syncState: SyncState = SyncState.localOnly

    public var date: Date
    public var durationSeconds: Int
    public var distanceMeters: Double
    public var notes: String?

    // Optional GPS route encoded as a polyline string (Google encoded polyline or similar)
    public var routePolyline: String?

    public var totalPoints: Double = 0

    public init(id: UUID = UUID(), date: Date = Date(), durationSeconds: Int, distanceMeters: Double, notes: String? = nil, routePolyline: String? = nil) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.date = date
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.notes = notes
        self.routePolyline = routePolyline
    }

    // Computed helpers (not persisted)
    public var paceSecondsPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        let km = distanceMeters / 1000.0
        return Double(durationSeconds) / km
    }

    public var distanceKm: Double {
        return distanceMeters / 1000.0
    }
}

// MARK: - Goals

@Model
public final class RunningGoal {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    /// Objetivo de kilómetros por semana
    public var weeklyKilometers: Double

    public init(id: UUID = UUID(), weeklyKilometers: Double = 0) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.weeklyKilometers = weeklyKilometers
    }
}

@Model
public final class GymGoal {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    /// Objetivos por grupo muscular: nº de entrenos/semana
    public var targetChestBack: Int
    public var targetArms: Int
    public var targetLegs: Int
    public var targetCore: Int

    public init(id: UUID = UUID(),
                targetChestBack: Int = 0,
                targetArms: Int = 0,
                targetLegs: Int = 0,
                targetCore: Int = 0) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.targetChestBack = targetChestBack
        self.targetArms = targetArms
        self.targetLegs = targetLegs
        self.targetCore = targetCore
    }

    public var totalWeeklyTarget: Int {
        targetChestBack + targetArms + targetLegs + targetCore
    }
}

// =========================
// WATCH RUNNING DETAIL MODELS
// =========================

@Model
public final class RunningWatchDetail {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    // Relación unidireccional: detalle -> sesión existente
    @Relationship(deleteRule: .nullify)
    public var session: RunningSession?

    // Series opcionales
    @Relationship(deleteRule: .cascade) public var hrPoints: [WatchHRPoint] = []
    @Relationship(deleteRule: .cascade) public var pacePoints: [WatchPacePoint] = []
    @Relationship(deleteRule: .cascade) public var elevationPoints: [WatchElevationPoint] = []

    // Splits por kilómetro
    @Relationship(deleteRule: .cascade) public var splits: [RunningWatchSplit] = []

    // Ruta opcional (futuro)
    public var routePolyline: String?

    public init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// Puntos de serie (t, v) — prefijo Watch para evitar colisiones de nombres
@Model
public final class WatchHRPoint {
    public var id: UUID
    public var t: Double          // segundos desde inicio
    public var v: Double          // bpm
    @Relationship(deleteRule: .nullify) public var detail: RunningWatchDetail?

    public init(id: UUID = UUID(), t: Double, v: Double) {
        self.id = id; self.t = t; self.v = v
    }
}

@Model
public final class WatchPacePoint {
    public var id: UUID
    public var t: Double          // segundos desde inicio
    public var v: Double          // m/s
    @Relationship(deleteRule: .nullify) public var detail: RunningWatchDetail?

    public init(id: UUID = UUID(), t: Double, v: Double) {
        self.id = id; self.t = t; self.v = v
    }
}

@Model
public final class WatchElevationPoint {
    public var id: UUID
    public var t: Double          // segundos desde inicio
    public var v: Double          // metros
    @Relationship(deleteRule: .nullify) public var detail: RunningWatchDetail?

    public init(id: UUID = UUID(), t: Double, v: Double) {
        self.id = id; self.t = t; self.v = v
    }
}

// Split por km
@Model
public final class RunningWatchSplit {
    public var id: UUID
    public var index: Int
    public var startOffset: Double
    public var endOffset: Double
    public var duration: Double
    public var distanceMeters: Double
    public var avgHR: Double?
    public var avgSpeed: Double?   // m/s
    @Relationship(deleteRule: .nullify) public var detail: RunningWatchDetail?

    public init(id: UUID = UUID(),
                index: Int,
                startOffset: Double,
                endOffset: Double,
                duration: Double,
                distanceMeters: Double,
                avgHR: Double?,
                avgSpeed: Double?) {
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


// MARK: - Body Measurements

public enum MeasurementKind: String, CaseIterable, Identifiable, Codable {
    case weight
    case waist, chest, hips
    case biceps, forearm
    case thigh, calf
    case neck, shoulders

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weight:   return "Weight"
        case .waist:    return "Waist"
        case .chest:    return "Chest"
        case .hips:     return "Hips"
        case .biceps:   return "Biceps"
        case .forearm:  return "Forearm"
        case .thigh:    return "Thigh"
        case .calf:     return "Calf"
        case .neck:     return "Neck"
        case .shoulders:return "Shoulders"
        }
    }

    /// true si es longitud (cm/in); false si es peso (kg/lb)
    public var isLength: Bool { self != .weight }
}

@Model
public final class BodyMeasurement {
    public var id: UUID
    public var date: Date
    /// Guardamos el tipo como raw para consultas sencillas
    public var kindRaw: String
    /// Valor **normalizado**:
    ///  - cm para longitudes
    ///  - kg para peso
    public var value: Double
    public var note: String?

    public init(id: UUID = UUID(), date: Date, kind: MeasurementKind, value: Double, note: String? = nil) {
        self.id = id
        self.date = date
        self.kindRaw = kind.rawValue
        self.value = value
        self.note = note
    }

    public var kind: MeasurementKind {
        get { MeasurementKind(rawValue: kindRaw) ?? .waist }
        set { kindRaw = newValue.rawValue }
    }
}

