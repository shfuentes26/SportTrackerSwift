//
//  WatchWorkoutManager.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
// TTWatch Watch App -> WatchWorkoutManager.swift
import SwiftUI
import HealthKit
import WatchConnectivity

#if targetEnvironment(simulator)
// ------- SIMULADOR: sin HealthKit -------



@MainActor
final class WatchWorkoutManager: ObservableObject {
    @Published var isRunning = false
    @Published var status = "Sim Idle"
    private var timer: Timer?
    private var startDate: Date?
    private var km: Double = 0
    private var hr: Int = 110
    private var hrSum: Int = 0        // ⬅️ nuevo
    private var hrCount: Int = 0      // ⬅️ nuevo

    func requestAuthorization() { status = "Sim Authorized" }

    func start() {
        status = "Sim Running…"
        isRunning = true
        startDate = Date()
        km = 0; hr = 110
        hrSum = 0; hrCount = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }   // ⬅️ filtro
            self.km += 0.01
            self.hr = min(175, max(90, self.hr + Int.random(in: -2...3)))
            self.hrSum += self.hr; self.hrCount += 1
            let elapsed = Date().timeIntervalSince(self.startDate ?? Date())
            WatchSession.shared.sendUpdateSmart(hr: self.hr, distanceKm: self.km, elapsed: elapsed)
            self.status = String(format: "HR %d • %.2f km", self.hr, self.km)
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate(); timer = nil
        let elapsed = Date().timeIntervalSince(self.startDate ?? Date())
        WatchSession.shared.sendUpdateSmart(hr: hr, distanceKm: km, elapsed: elapsed)

        let avg = hrCount > 0 ? hrSum / hrCount : 0
        let summary: [String: Any] = [
            "type": "summary",
            "start": (startDate ?? Date()).timeIntervalSince1970,
            "end": Date().timeIntervalSince1970,
            "dist": km,
            "avgHR": avg
        ]

        // 1) Entrega inmediata si el iPhone está en foreground
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(summary, replyHandler: nil, errorHandler: nil)
        }

        // 2) Garantía de entrega cuando vuelva al foreground
        WCSession.default.transferUserInfo(summary)

        status = "Sim Finished"
    }
}
#else
// ------- DISPOSITIVO REAL: HealthKit -------
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var status: String = "Idle"

    private var healthStore: HKHealthStore? = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var startDate: Date?
    private var km: Double = 0          // ⬅️ nuevo: guarda distancia acumulada
    private var hrSum: Int = 0          // ⬅️ nuevo
    private var hrCount: Int = 0        // ⬅️ nuevo

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
        
        isRunning = true
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
            km = 0; hrSum = 0; hrCount = 0

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
        isRunning = false
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            guard let self else { return }
            self.builder?.finishWorkout { _, error in
                Task { @MainActor in
                    self.status = (error == nil) ? "Finished" : "Finish error"

                    // Enviar resumen final
                    let avg = self.hrCount > 0 ? self.hrSum / self.hrCount : 0
                    let summary: [String: Any] = [
                        "type": "summary",
                        "start": (self.startDate ?? Date()).timeIntervalSince1970,
                        "end": Date().timeIntervalSince1970,
                        "dist": self.km,
                        "avgHR": avg
                    ]

                    // Inmediato si reachable
                    if WCSession.default.isReachable {
                        WCSession.default.sendMessage(summary, replyHandler: nil, errorHandler: nil)
                    }

                    // Garantizado en background
                    WCSession.default.transferUserInfo(summary)
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

    // Requerido en watchOS recientes: enviar updates al iPhone
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var hrBpm: Int = 0
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(hrType),
           let stats = workoutBuilder.statistics(for: hrType) {
            let unit = HKUnit(from: "count/min")
            hrBpm = Int(stats.mostRecentQuantity()?.doubleValue(for: unit) ?? 0)
            if hrBpm > 0 { hrSum += hrBpm; hrCount += 1 } // ⬅️ acumula HR
        }

        var distKm: Double = km
        if let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
           collectedTypes.contains(distType),
           let stats = workoutBuilder.statistics(for: distType) {
            distKm = (stats.sumQuantity()?.doubleValue(for: .meter()) ?? 0) / 1000.0
            km = distKm // ⬅️ guarda la última distancia acumulada
        }

        let elapsed = Date().timeIntervalSince(startDate ?? Date())
        WatchSession.shared.sendUpdateSmart(hr: hrBpm, distanceKm: distKm, elapsed: elapsed)
        Task { @MainActor in self.status = "HR \(hrBpm) • \(String(format: "%.2f", distKm)) km" }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}
#endif
