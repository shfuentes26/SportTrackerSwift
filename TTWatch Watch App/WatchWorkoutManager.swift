//
//  WatchWorkoutManager.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
// TTWatch Watch App -> WatchWorkoutManager.swift
import SwiftUI
import HealthKit

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var status: String = "Idle"

    private var healthStore: HKHealthStore? = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable(), let healthStore else {
            status = "Health not available"
            return
        }
        let toShare: Set = [HKObjectType.workoutType()]
        let toRead: Set = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
        healthStore.requestAuthorization(toShare: toShare, read: toRead) { [weak self] ok, _ in
            Task { @MainActor in self?.status = ok ? "Authorized" : "Auth failed" }
        }
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), let healthStore else {
            status = "No HealthKit"
            return
        }
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .running
        cfg.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: cfg)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: cfg)
            session.delegate = self
            builder.delegate = self
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] _, _ in
                Task { @MainActor in self?.status = "Running…" }
            }
            self.session = session
            self.builder = builder
        } catch {
            status = "Failed to start: \(error.localizedDescription)"
        }
    }

    func stop() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, error in
                Task { @MainActor in
                    self?.status = (error == nil) ? "Finished" : "Finish error"
                }
            }
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) { }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.status = "Session error: \(error.localizedDescription)" }
    }

    // Requerido en watchOS recientes
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(hrType),
           let stats = workoutBuilder.statistics(for: hrType) {
            let unit = HKUnit(from: "count/min")
            let hr = stats.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
            Task { @MainActor in self.status = "HR: \(Int(hr)) bpm" }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}
