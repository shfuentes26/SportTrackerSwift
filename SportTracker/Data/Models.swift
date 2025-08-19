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
    public var syncState: SyncState = SyncState.localOnly

    // Scoring factors (tune in UI later)
    public var runningDistanceFactor: Double = 10.0       // pts per km
    public var runningTimeFactor: Double = 0.5            // pts per minute
    public var runningPaceBaselineSecPerKm: Double = 360  // 6:00 min/km baseline
    public var runningPaceFactor: Double = 50.0           // weight of pace score

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

    public init(id: UUID = UUID(), name: String, muscleGroup: MuscleGroup, isWeighted: Bool, exerciseDescription: String? = nil, iconSystemName: String? = nil, imageData: Data? = nil, isCustom: Bool = true) {
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
