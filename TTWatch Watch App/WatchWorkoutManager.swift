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
import CoreLocation

#if targetEnvironment(simulator)
// ------- SIMULADOR: sin HealthKit -------

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var status = "Sim Idle"

    private var timer: Timer?
    private var startDate: Date?
    private var km: Double = 0
    private var hr: Int = 110
    private var hrSum: Int = 0
    private var hrCount: Int = 0

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

    // Localización (solo para registrar la ruta simulada)
    private let location = CLLocationManager()
    private var routeCoords: [CLLocationCoordinate2D] = []

    // Elevación
    private var elevationSeries: [TimedSample<Double>] = []
    private var lastAltitude: CLLocationDistance? = nil
    private var totalAscentMeters: Double = 0

    // Live metrics para la UI
    @Published var liveStartDate: Date? = nil
    @Published var liveKm: Double = 0
    @Published var liveHR: Int? = nil
    @Published var livePaceSecPerKm: Double? = nil

    @Published var isPaused = false

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true                  // (en sim solo congelamos la simulación)
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
    }

    func requestAuthorization() {
        status = "Sim Authorized"
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
    }

    func start() {
        status = "Sim Running…"
        isRunning = true
        isPaused = false
        let start = Date()
        startDate = start
        liveStartDate = start

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
        liveKm = 0
        liveHR = hr
        livePaceSecPerKm = nil

        elevationSeries.removeAll()
        lastAltitude = nil
        totalAscentMeters = 0

        routeCoords.removeAll()
        location.startUpdatingLocation()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isRunning, !self.isPaused else { return }

            // simulamos distancia y HR
            self.km += 0.01
            self.hr = min(175, max(90, self.hr + Int.random(in: -2...3)))
            self.liveKm = self.km
            self.liveHR = self.hr

            let now = Date()
            let elapsed = now.timeIntervalSince(self.startDate ?? now)

            // HR para series/promedios
            self.hrSum += self.hr; self.hrCount += 1
            self.hrSeries.append(TimedSample(t: elapsed, v: Double(self.hr)))

            // Velocidad/pace desde delta de distancia simulada
            let distMeters = self.km * 1000.0
            if let lastT = self.lastSampleDate {
                let dt = now.timeIntervalSince(lastT)
                if dt > 0 {
                    let dv = max(0, distMeters - self.lastDistMeters)
                    let speed = dv / dt                  // m/s
                    self.paceSeries.append(TimedSample(t: elapsed, v: speed))
                    self.livePaceSecPerKm = speed > 0 ? (1000.0 / speed) : nil
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

            self.status = String(format: "HR %d • %.2f km", self.hr, self.km)
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate(); timer = nil
        location.stopUpdatingLocation()

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
            elevationSeries: elevationSeries,
            totalAscent: totalAscentMeters,
            route: nil,
            kmSplits: kmSplits
        )

        do {
            let url = try WorkoutPayloadIO.write(payload)

            // Adjuntamos la polyline en el metadata
            var meta = payload.makeTransferMetadata()
            meta["routePolyline"] = Polyline.encode(self.routeCoords)
            let tf = WCSession.default.transferFile(url, metadata: meta)

            print("[WC][watch] queued after enqueue:",
                  WCSession.default.outstandingFileTransfers.count,
                  "isTransferring:", tf.isTransferring)
            status = "Sim Finished • sent"
        } catch {
            status = "Sim Finish error: \(error.localizedDescription)"
        }
    }
}

// CLLocation SOLO para sim: guardamos la ruta (no calculamos distancia real)
extension WatchWorkoutManager: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning else { return }
        for loc in locations {
            guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 50 else { continue }
            if let last = routeCoords.last {
                let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
                if d < 5 { continue }
            }
            routeCoords.append(loc.coordinate)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.status = "Location error: \(error.localizedDescription)" }
    }
}

#else
// ------- DISPOSITIVO REAL: HealthKit -------
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var status: String = "Idle"
    // Live metrics para la UI
    @Published var liveStartDate: Date? = nil
    @Published var liveKm: Double = 0
    @Published var liveHR: Int? = nil
    @Published var livePaceSecPerKm: Double? = nil

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
    
    // Localización
    private let location = CLLocationManager()
    private var routeCoords: [CLLocationCoordinate2D] = []
    
    // Elevación
    private var elevationSeries: [TimedSample<Double>] = []  // (t: seconds, v: meters)
    private var lastAltitude: CLLocationDistance? = nil
    private var totalAscentMeters: Double = 0
    
    // Acumulación de distancia vía GPS
    private var lastLocForDist: CLLocation?
    private var totalDistMeters: Double = 0
    
    @Published var isPaused = false
    
    private func setFrontmostTimeout(_ on: Bool) {
    #if os(watchOS)
        WKExtension.shared().isFrontmostTimeoutExtended = on
    #endif
    }
    

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        // Si usas HealthKit en real:
        session?.pause()
       // builder?.pauseCollection(withStart: Date())
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        session?.resume()
        //builder?.resumeCollection(withStart: Date())
    }

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
        isPaused = false
        guard HKHealthStore.isHealthDataAvailable(), let healthStore else {
            status = "No HealthKit"; return
        }
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .running
        cfg.locationType = .outdoor
        setFrontmostTimeout(true)

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: cfg)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: cfg)
            session.delegate = self
            builder.delegate = self

            let start = Date()
            startDate = start
            liveStartDate = start
            liveKm = 0
            liveHR = nil
            livePaceSecPerKm = nil
            totalDistMeters = 0
            lastLocForDist = nil
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
            
            elevationSeries.removeAll()
            lastAltitude = nil
            totalAscentMeters = 0
            
            
            routeCoords.removeAll()
            location.delegate = self
            location.activityType = .fitness
            location.desiredAccuracy = kCLLocationAccuracyBest
            location.distanceFilter = 5   // ignora micro-movimientos < 5 m
            if location.authorizationStatus == .notDetermined {
                location.requestWhenInUseAuthorization()
            }
            
            
            location.startUpdatingLocation()

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
        location.stopUpdatingLocation()
        
        setFrontmostTimeout(false)

        let end = Date()
        let start = self.startDate ?? end
        let duration = end.timeIntervalSince(start)
        let avg = self.hrCount > 0 ? Double(self.hrSum) / Double(self.hrCount) : 0
        // Distancia final: usa HK si llegó, si no, cae al GPS; y en general quédate con el mayor.
        let distMetersHK  = self.km * 1000.0
        let distMetersGPS = self.totalDistMeters
        let distMeters    = max(distMetersHK, distMetersGPS)

        func cleanup() {
                location.stopUpdatingLocation()
                setFrontmostTimeout(false)
                // invalida timers propios si los hubiera
                // anula referencias para que no retengan la app
                self.builder = nil
                self.session = nil
            }

        func sendPayloadAndCleanup() {
            // ... tu payload ...
            cleanup()
        }
        
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
                elevationSeries: elevationSeries,
                totalAscent: totalAscentMeters,
                route: nil,
                kmSplits: self.kmSplits
            )
            do {
                let url = try WorkoutPayloadIO.write(payload)
                var meta = payload.makeTransferMetadata()
                meta["routePolyline"] = Polyline.encode(self.routeCoords)
                let tf = WCSession.default.transferFile(url, metadata: meta)
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
            // Failsafe por si los closures no vuelven (10 s)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                        guard let self else { return }
                        if self.session != nil || self.builder != nil {
                            // algo quedó colgado; fuerza cierre
                            self.session?.end()
                            sendPayloadAndCleanup()
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
                liveHR = hrBpm
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

enum Polyline {
    static func encode(_ coords: [CLLocationCoordinate2D]) -> String {
        var res = ""
        var lastLat = 0
        var lastLon = 0
        for c in coords {
            let lat = Int(round(c.latitude * 1e5))
            let lon = Int(round(c.longitude * 1e5))
            res += enc(lat - lastLat)
            res += enc(lon - lastLon)
            lastLat = lat; lastLon = lon
        }
        return res
    }
    private static func enc(_ v: Int) -> String {
        var x = v << 1; if v < 0 { x = ~x }
        var out = ""
        while x >= 0x20 {
            out.append(Character(UnicodeScalar((0x20 | (x & 0x1f)) + 63)!))
            x >>= 5
        }
        out.append(Character(UnicodeScalar(x + 63)!))
        return out
    }
}

// Esta extensión es SOLO para dispositivo real (usa símbolos que no existen en sim)
#if !targetEnvironment(simulator)

import CoreLocation

extension WatchWorkoutManager: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning, !isPaused else { return }
        for loc in locations {
            guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 50 else { continue }
            
            // Distancia por GPS para la métrica en vivo
            if let prev = lastLocForDist {
                // 2.1 Recencia (muestras muy viejas pueden “pegar saltos”):
                guard abs(loc.timestamp.timeIntervalSinceNow) < 3 else {
                    lastLocForDist = loc
                    continue
                }

                let dv = loc.distance(from: prev)                  // metros avanzados
                let dt = loc.timestamp.timeIntervalSince(prev.timestamp)

                // 2.2 Paso mínimo dinámico: al menos precisión o 3 m
                let minStep = max(3.0, loc.horizontalAccuracy)
                guard dv >= minStep, dt > 0 else {
                    lastLocForDist = loc
                    continue
                }

                // 2.3 Acumula (igual que ya haces)
                totalDistMeters += dv
                liveKm = totalDistMeters / 1000.0
                //liveKm = km

                let speed = dv / dt                                 // m/s
                livePaceSecPerKm = speed > 0 ? (1000.0 / speed) : nil
            }
            lastLocForDist = loc
            
            
            if let last = routeCoords.last {
                let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
                if d < 5 { continue }
            }
            routeCoords.append(loc.coordinate)
        }
    }
}
#endif
