//
//  HealthKitManager.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//
import Foundation
import HealthKit

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private init() {}
    
    private let healthStore = HKHealthStore()
    private let lastImportKey = "HealthKitLastImportDate"

    // Tipos a leer
    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let dist = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            set.insert(dist)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            set.insert(energy)
        }
        if #available(iOS 11.0, *) {
                set.insert(HKSeriesType.workoutRoute())
        }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            set.insert(hr)
        }
        // En readTypes, suma bodyMass
        if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            set.insert(mass)
        }
        return set
    }

    // Solicitar permisos
    func requestAuthorization() async throws {
        //HealthKitManager.requestAuthorization()
        let hasKey = Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil
        assert(hasKey, "Missing NSHealthShareUsageDescription in Info.plist")
        print("Bundle:", Bundle.main.bundleIdentifier ?? "nil")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard success else {
                    cont.resume(throwing: NSError(
                        domain: "HealthKit",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Health permissions were not granted."]
                    ))
                    return
                }
                cont.resume(returning: ())
            }
        }
    }
    // Fecha del último import
    var lastImportDate: Date {
        get { UserDefaults.standard.object(forKey: lastImportKey) as? Date ?? Date(timeIntervalSince1970: 0) }
        set { UserDefaults.standard.set(newValue, forKey: lastImportKey) }
    }
    
    func fetchBodyMassSamples(since start: Date? = nil) async throws -> [HKQuantitySample] {
        try await ensureAvailability()
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }

        let from = start ?? Date(timeIntervalSince1970: 0)
        let pred = HKQuery.predicateForSamples(withStart: from, end: Date(), options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: sort) {
                _, res, err in
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(q)
        }
    }

    struct ImportedWorkout: Identifiable {
        let id: String                   // HK UUID string
        let start: Date
        let end: Date
        let activity: HKWorkoutActivityType
        let durationSec: Double
        let distanceMeters: Double?
        let activeCalories: Double?
    }

    // Leer workouts desde la última importación
    func fetchNewWorkouts() async throws -> [ImportedWorkout] {
        try await ensureAvailability()

        let workoutType = HKObjectType.workoutType()

        // Solo entrenamientos .running desde la última importación
        let datePredicate = HKQuery.predicateForSamples(withStart: lastImportDate, end: Date(), options: .strictEndDate)
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runningPredicate])

        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[ImportedWorkout], Error>) in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) {
                _, results, error in
                if let error = error {
                    cont.resume(throwing: error); return
                }
                let workouts = (results as? [HKWorkout]) ?? []
                let mapped = workouts.map { wk in
                    ImportedWorkout(
                        id: wk.uuid.uuidString,
                        start: wk.startDate,
                        end: wk.endDate,
                        activity: wk.workoutActivityType,              // será .running
                        durationSec: wk.duration,
                        distanceMeters: wk.totalDistance?.doubleValue(for: .meter()),
                        activeCalories: wk.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    )
                }
                cont.resume(returning: mapped)
            }
            self.healthStore.execute(query)
        }
    
    }
    
    func fetchNewHKWorkouts() async throws -> [HKWorkout] {
        try await ensureAvailability()

        let workoutType = HKObjectType.workoutType()
        let datePredicate = HKQuery.predicateForSamples(withStart: lastImportDate, end: Date(), options: .strictEndDate)
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runningPredicate])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) {
                _, results, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            self.healthStore.execute(query)
        }
    }

    // Opcional: filtra solo actividades que te interesan
    func filterSupported(_ workouts: [ImportedWorkout]) -> [ImportedWorkout] {
        workouts.filter { $0.activity == .running }
    }

    // Llamar tras importar con éxito
    func markImported(upTo date: Date = Date()) {
        lastImportDate = date
    }

    private func ensureAvailability() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKit", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Health data is not available on this device."])
        }
    }
}

