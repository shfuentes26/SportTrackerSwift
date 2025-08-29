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
import Foundation

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
    // Series para enviar al iPhone
    private var hrSeries: [TimedSample<Double>] = []
    private var paceSeries: [TimedSample<Double>] = []

    // Para calcular velocidad instantánea
    private var lastSampleDate: Date?
    private var lastDistMeters: Double = 0

    // Splits por kilómetro
    private var kmSplits: [KilometerSplit] = []
    private var splitIndex: Int = 0
    private var splitStartElapsed: TimeInterval = 0
    private var splitStartDist: Double = 0
    private var splitHrSum: Int = 0
    private var splitHrCount: Int = 0

    func requestAuthorization() { status = "Sim Authorized" }

    func start() {
        status = "Sim Running…"
        isRunning = true
        startDate = Date()
        
        hrSeries = []
        paceSeries = []
        lastSampleDate = nil
        lastDistMeters = 0

        kmSplits = []
        splitIndex = 0
        splitStartElapsed = 0
        splitStartDist = 0
        splitHrSum = 0
        splitHrCount = 0
        
        km = 0; hr = 110
        hrSum = 0; hrCount = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.km += 0.01
            self.hr = min(175, max(90, self.hr + Int.random(in: -2...3)))

            // acumular HR promedio global
            self.hrSum += self.hr; self.hrCount += 1

            let now = Date()
            let elapsed = now.timeIntervalSince(self.startDate ?? now)

            // Serie HR
            self.hrSeries.append(TimedSample(t: elapsed, v: Double(self.hr)))

            // Serie velocidad (m/s) a partir de delta distancia
            let distMeters = self.km * 1000.0
            if let lastT = self.lastSampleDate {
                let dt = now.timeIntervalSince(lastT)
                if dt > 0 {
                    let dv = max(0, distMeters - self.lastDistMeters)
                    let speed = dv / dt
                    self.paceSeries.append(TimedSample(t: elapsed, v: speed))
                }
            }
            self.lastSampleDate = now

            // Splits por km
            let prevKmFloor = Int(floor(self.lastDistMeters / 1000.0))
            let currKmFloor = Int(floor(distMeters / 1000.0))
            if currKmFloor > prevKmFloor {
                let splitDistance = distMeters - self.splitStartDist
                let splitDuration = elapsed - self.splitStartElapsed
                let avgHRSplit = self.splitHrCount > 0 ? Double(self.splitHrSum) / Double(self.splitHrCount) : nil
                let avgSpeedSplit = splitDuration > 0 ? splitDistance / splitDuration : nil

                self.kmSplits.append(KilometerSplit(
                    index: self.splitIndex + 1,
                    startOffset: self.splitStartElapsed,
                    endOffset: elapsed,
                    duration: splitDuration,
                    distanceMeters: splitDistance,
                    avgHR: avgHRSplit,
                    avgSpeed: avgSpeedSplit
                ))
                self.splitIndex += 1
                self.splitStartElapsed = elapsed
                self.splitStartDist = distMeters
                self.splitHrSum = 0
                self.splitHrCount = 0
            }

            self.lastDistMeters = distMeters
            self.splitHrSum += self.hr
            self.splitHrCount += 1

            // ❌ ya NO mandamos realtime
            self.status = String(format: "HR %d • %.2f km", self.hr, self.km)
        }

    }

    func stop() {
        isRunning = false
        timer?.invalidate(); timer = nil

        let end = Date()
        let start = self.startDate ?? end
        let duration = end.timeIntervalSince(start)
        let avg = hrCount > 0 ? Double(hrSum) / Double(hrCount) : 0
        let distMeters = km * 1000.0

        let payload = WorkoutPayload(
            start: start,
            end: end,
            duration: duration,
            distanceMeters: distMeters,
            totalEnergyKcal: nil,
            avgHR: avg,
            hrSeries: hrSeries,
            paceSeries: paceSeries,
            route: nil,
            kmSplits: kmSplits
        )

        do {
            let url = try WorkoutPayloadIO.write(payload)
            let tf = WCSession.default.transferFile(url, metadata: payload.makeTransferMetadata())
            print("[WC][watch] queued after enqueue:",
                  WCSession.default.outstandingFileTransfers.count,
                  "isTransferring:", tf.isTransferring)
            status = "Sim Finished • sent"
        } catch {
            status = "Sim Finish error: \(error.localizedDescription)"
        }
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
    
    // Series para enviar al iPhone
    private var hrSeries: [TimedSample<Double>] = []
    private var paceSeries: [TimedSample<Double>] = []

    // Para calcular velocidad instantánea
    private var lastSampleDate: Date?
    private var lastDistMeters: Double = 0

    // Splits por kilómetro
    private var kmSplits: [KilometerSplit] = []
    private var splitIndex: Int = 0
    private var splitStartElapsed: TimeInterval = 0
    private var splitStartDist: Double = 0
    private var splitHrSum: Int = 0
    private var splitHrCount: Int = 0

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
            hrSeries = []
            paceSeries = []
            lastSampleDate = nil
            lastDistMeters = 0

            kmSplits = []
            splitIndex = 0
            splitStartElapsed = 0
            splitStartDist = 0
            splitHrSum = 0
            splitHrCount = 0
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

        let end = Date()
        let start = self.startDate ?? end
        let duration = end.timeIntervalSince(start)
        let avg = self.hrCount > 0 ? Double(self.hrSum) / Double(self.hrCount) : 0
        let distMeters = self.km * 1000.0

        // Construye una función local para enviar el fichero una sola vez
        func sendPayload() {
            let payload = WorkoutPayload(
                start: start,
                end: end,
                duration: duration,
                distanceMeters: distMeters,
                totalEnergyKcal: nil,
                avgHR: avg,
                hrSeries: self.hrSeries,
                paceSeries: self.paceSeries,
                route: nil,
                kmSplits: self.kmSplits
            )
            do {
                let url = try WorkoutPayloadIO.write(payload)
                let tf = WCSession.default.transferFile(url, metadata: payload.makeTransferMetadata())
                print("[WC][watch] queued after enqueue:",
                      WCSession.default.outstandingFileTransfers.count,
                      "isTransferring:", tf.isTransferring)
                self.status = "Finished • sent"
            } catch {
                self.status = "Finish error: \(error.localizedDescription)"
            }
        }

        // Cierra correctamente el builder y la sesión; luego envía
        if let builder, let session {
            builder.endCollection(withEnd: end) { [weak self] _, _ in
                guard let self else { return }
                session.end()
                builder.finishWorkout { _, _ in
                    Task { @MainActor in sendPayload() }
                }
            }
        } else {
            // Por si no había sesión activa (fall-safe)
            sendPayload()
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
        let now = Date()
        let elapsed = now.timeIntervalSince(startDate ?? now)

        // HR
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(hrType),
           let stats = workoutBuilder.statistics(for: hrType) {
            let unit = HKUnit(from: "count/min")
            hrBpm = Int(stats.mostRecentQuantity()?.doubleValue(for: unit) ?? 0)
            if hrBpm > 0 {
                hrSum += hrBpm; hrCount += 1
                hrSeries.append(TimedSample(t: elapsed, v: Double(hrBpm)))
                // acumular para split actual
                splitHrSum += hrBpm
                splitHrCount += 1
            }
        }

        // Distancia y velocidad
        var distKm: Double = km
        if let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
           collectedTypes.contains(distType),
           let stats = workoutBuilder.statistics(for: distType) {
            distKm = (stats.sumQuantity()?.doubleValue(for: .meter()) ?? 0) / 1000.0
            km = distKm

            let distMeters = distKm * 1000.0
            if let lastT = lastSampleDate {
                let dt = now.timeIntervalSince(lastT)
                if dt > 0 {
                    let dv = max(0, distMeters - lastDistMeters)
                    let speed = dv / dt
                    paceSeries.append(TimedSample(t: elapsed, v: speed))
                }
            }

            // Splits por km (cerrar cuando cruce)
            let prevKmFloor = Int(floor(lastDistMeters / 1000.0))
            let currKmFloor = Int(floor(distMeters / 1000.0))
            if currKmFloor > prevKmFloor {
                let splitDistance = distMeters - splitStartDist
                let splitDuration = elapsed - splitStartElapsed
                let avgHRSplit = splitHrCount > 0 ? Double(splitHrSum) / Double(splitHrCount) : nil
                let avgSpeedSplit = splitDuration > 0 ? splitDistance / splitDuration : nil

                kmSplits.append(KilometerSplit(
                    index: splitIndex + 1,
                    startOffset: splitStartElapsed,
                    endOffset: elapsed,
                    duration: splitDuration,
                    distanceMeters: splitDistance,
                    avgHR: avgHRSplit,
                    avgSpeed: avgSpeedSplit
                ))
                splitIndex += 1
                splitStartElapsed = elapsed
                splitStartDist = distMeters
                splitHrSum = 0
                splitHrCount = 0
            }

            lastSampleDate = now
            lastDistMeters = distMeters
        }

        // ❌ ya NO mandamos realtime
        Task { @MainActor in
            self.status = "HR \(hrBpm) • \(String(format: "%.2f", distKm)) km"
        }

    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}
#endif
