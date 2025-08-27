//
//  WatchWorkoutManager.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
// TTWatch Watch App -> WatchWorkoutManager.swift
import SwiftUI
import HealthKit

#if targetEnvironment(simulator)
// ------- SIMULADOR: sin HealthKit -------
@MainActor
final class WatchWorkoutManager: ObservableObject {
    @Published var status = "Sim Idle"
    private var timer: Timer?
    private var startDate: Date?
    private var km: Double = 0
    private var hr: Int = 110

    func requestAuthorization() { status = "Sim Authorized" }

    func start() {
        status = "Sim Running…"
        startDate = Date()
        km = 0; hr = 110
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            print("SIM TICK hr=\(self.hr) km=\(self.km)")
            self.km += 0.01                          // ~10m/s para demo
            self.hr = min(175, max(90, self.hr + Int.random(in: -2...3)))
            let elapsed = Date().timeIntervalSince(self.startDate ?? Date())
            WatchSession.shared.sendUpdate(hr: self.hr, distanceKm: self.km, elapsed: elapsed)
            self.status = String(format: "HR %d • %.2f km", self.hr, self.km)
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        let elapsed = Date().timeIntervalSince(self.startDate ?? Date())
        WatchSession.shared.sendUpdate(hr: hr, distanceKm: km, elapsed: elapsed)
        status = "Sim Finished"
    }
}
#else
// ------- DISPOSITIVO REAL: HealthKit -------
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var status: String = "Idle"

    private var healthStore: HKHealthStore? = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?

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
            status = "No HealthKit"; return
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
            startDate = start
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

    // Requerido en watchOS recientes: enviamos updates al iPhone
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var hrBpm: Int = 0
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(hrType),
           let stats = workoutBuilder.statistics(for: hrType) {
            let unit = HKUnit(from: "count/min")
            hrBpm = Int(stats.mostRecentQuantity()?.doubleValue(for: unit) ?? 0)
        }

        var km: Double = 0
        if let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
           collectedTypes.contains(distType),
           let stats = workoutBuilder.statistics(for: distType) {
            km = (stats.sumQuantity()?.doubleValue(for: .meter()) ?? 0) / 1000.0
        }

        let elapsed = Date().timeIntervalSince(startDate ?? Date())
        WatchSession.shared.sendUpdate(hr: hrBpm, distanceKm: km, elapsed: elapsed)
        Task { @MainActor in self.status = "HR \(hrBpm) • \(String(format: "%.2f", km)) km" }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}
#endif
