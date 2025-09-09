import Foundation
import SwiftData
import HealthKit
import CoreLocation

enum HealthKitImportService {

    /// Guarda en SwiftData solo entrenamientos de running (HKWorkout ya filtrado por tu manager).
    /// Devuelve cuántos se insertaron.
    static func saveToLocal(_ workouts: [HealthKitManager.ImportedWorkout],
                            context: ModelContext) throws -> Int {
        
        print("[HealthKitImportService]saveToLocal is called")
        var inserted = 0
        
        // Obtener settings existentes (o crear uno si no hay)
        let settings: Settings = try context.fetch(FetchDescriptor<Settings>()).first
            ?? {
                let s = Settings()
                context.insert(s)
                return s
            }()

        for wk in workouts {
            // Solo running con distancia válida
            guard wk.activity == .running, let distM = wk.distanceMeters, distM > 0 else { continue }

            let run = RunningSession(
                date: wk.start,
                durationSeconds: Int(wk.durationSec.rounded()),
                distanceMeters: distM,
                notes: "Imported from Apple Health"
            )
            // 👉 Calcular y asignar puntos aquí
            run.totalPoints = PointsCalculator.score(running: run, settings: settings)
            
            context.insert(run)
            inserted += 1
        }
        
        try context.save()
        if inserted > 0 { print("[HK][SAVE] inserted: \(inserted)") } // LOG corto
        return inserted
    }

    // MARK: - FALLBACK desde muestras de distancia (para diferenciar running de walking)

    struct DistanceSession {
        let start: Date
        let end: Date
        let distanceMeters: Double
        var durationSec: Double { end.timeIntervalSince(start) }
    }
    
    // Datos listos para UI
    struct RunMetrics {
        // Pace por km
        struct Split: Identifiable { let id = UUID(); let km: Int; let seconds: Double }
        let splits: [Split]

        // Serie temporal (opcional si luego quieres trazar línea)
        let paceSeries: [(time: TimeInterval, secPerKm: Double)]  // tiempo desde inicio, s/km

        // Elevación
        let elevationSeries: [(time: TimeInterval, meters: Double)]
        let totalAscent: Double

        // HR
        let heartRateSeries: [(time: TimeInterval, bpm: Double)]
        let avgHR: Double?
        let maxHR: Double?
    }

    /// Reconstruye sesiones a partir de `distanceWalkingRunning` y filtra caminatas por umbrales.
    static func importFromDistanceSamples(
        context: ModelContext,
        daysBack: Int = 365,
        gapSeconds: TimeInterval = 15*60,
        minRunSpeedMS: Double = 2.1,   // ≈ 8:00 min/km
        minDistanceM: Double = 800,    // >= 0.8 km
        minDurationS: Double = 8*60    // >= 8 min
    ) async throws -> Int {
        let samples = try await fetchDistanceSamples(daysBack: daysBack)
        let sessions = groupSamplesIntoSessions(samples, gapSeconds: gapSeconds)

        var inserted = 0
        var skippedWalkingLike = 0

        for ss in sessions {
            let avgSpeed = ss.distanceMeters / max(ss.durationSec, 1)
            // Filtra sesiones que parecen caminatas (lentas/cortas)
            guard ss.distanceMeters >= minDistanceM,
                  ss.durationSec >= minDurationS,
                  avgSpeed >= minRunSpeedMS else {
                skippedWalkingLike += 1
                continue
            }

            let run = RunningSession(
                date: ss.start,
                durationSeconds: Int(ss.durationSec.rounded()),
                distanceMeters: ss.distanceMeters,
                notes: "Imported from Apple Health (derived from distance samples)"
            )
            print("[HealthKitImportService]importFromDistanceSamples is called")
            context.insert(run)
            inserted += 1
        }

        try context.save()
        if inserted > 0 {
            print("[HK][FALLBACK] inserted: \(inserted) (skipped as walking-like: \(skippedWalkingLike))")
        } else {
            print("[HK][FALLBACK] no sessions matched running thresholds; skipped: \(skippedWalkingLike)")
        }
        return inserted
    }

    private static func fetchDistanceSamples(daysBack: Int) async throws -> [HKQuantitySample] {
        print("[HealthKitImportService]fetchDistanceSamples is called")
        let hs = HKHealthStore()
        guard let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: distType,
                                  predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            hs.execute(q)
        }
    }

    /// Agrupa muestras contiguas; si el hueco entre una y otra supera `gapSeconds`, comienza una nueva sesión.
    private static func groupSamplesIntoSessions(_ samples: [HKQuantitySample], gapSeconds: TimeInterval) -> [DistanceSession] {
        print("[HealthKitImportService]groupSamplesIntoSessions is called")
        guard !samples.isEmpty else { return [] }
        var sessions: [DistanceSession] = []
        var curStart = samples[0].startDate
        var curEnd = samples[0].endDate
        var curDist = samples[0].quantity.doubleValue(for: .meter())

        for i in 1..<samples.count {
            let s = samples[i]
            let gap = s.startDate.timeIntervalSince(curEnd)
            if gap > gapSeconds {
                if curDist > 0 {
                    sessions.append(DistanceSession(start: curStart, end: curEnd, distanceMeters: curDist))
                }
                curStart = s.startDate
                curEnd = s.endDate
                curDist = 0
            }
            curEnd = max(curEnd, s.endDate)
            curDist += s.quantity.doubleValue(for: .meter())
        }
        if curDist > 0 {
            sessions.append(DistanceSession(start: curStart, end: curEnd, distanceMeters: curDist))
        }
        return sessions
    }
    
    /// Lee la(s) rutas GPS asociadas a un HKWorkout y devuelve una polyline (o nil si no hay).
    private static func fetchRoutePolyline(for workout: HKWorkout,
                                           healthStore: HKHealthStore) async -> String? {
        
        print("[HealthKitImportService]fetchRoutePolyline is called")
        let routeType = HKSeriesType.workoutRoute()
        // 1) Buscar todas las HKWorkoutRoute del workout
        let predicate = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: routeType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, error in
                guard error == nil,
                      let routes = samples as? [HKWorkoutRoute],
                      !routes.isEmpty else {
                    cont.resume(returning: nil)
                    return
                }

                var allCoords: [CLLocationCoordinate2D] = []
                let group = DispatchGroup()

                for route in routes {
                    group.enter()
                    var routeLocs: [CLLocation] = []
                    let rq = HKWorkoutRouteQuery(route: route) { _, locs, done, _ in
                        if let locs { routeLocs.append(contentsOf: locs) }
                        if done {
                            routeLocs.sort { $0.timestamp < $1.timestamp }
                            allCoords.append(contentsOf: routeLocs.map { $0.coordinate })
                            group.leave()
                        }
                    }
                    healthStore.execute(rq)
                }

                group.notify(queue: .main) {
                    guard !allCoords.isEmpty else { cont.resume(returning: nil); return }
                    // Usa tu encoder ya existente (enum Polyline de tu proyecto)
                    cont.resume(returning: Polyline.encode(allCoords))
                }
            }
            healthStore.execute(q)
        }
    }
    
    /// Guarda en SwiftData entrenamientos de running leídos como HKWorkout,
    /// incluyendo la ruta GPS si existe. Devuelve cuántos insertó.
    @MainActor
    static func saveHKWorkoutsToLocal(_ workouts: [HKWorkout],
                                      context: ModelContext,
                                      healthStore: HKHealthStore = HKHealthStore()) async throws -> Int {
        
        print("[HealthKitImportService]saveHKWorkoutsToLocal is called")
        var inserted = 0
        
        // Obtener settings existentes (o crear uno si no hay)
        let settings: Settings = try context.fetch(FetchDescriptor<Settings>()).first
            ?? {
                let s = Settings()
                context.insert(s)
                return s
            }()

        for wk in workouts {
            guard wk.workoutActivityType == .running else { continue }
            let distM = wk.totalDistance?.doubleValue(for: .meter()) ?? 0
            guard distM > 0 else { continue }
            
            // --- DEDUPE: ¿ya existe una sesión equivalente? ---
            let dur = Int(wk.duration.rounded())
            let minDate = wk.startDate.addingTimeInterval(-180)
            let maxDate = wk.startDate.addingTimeInterval(+180)
            let pred = #Predicate<RunningSession> { s in
                s.date >= minDate && s.date <= maxDate &&
                s.durationSeconds >= (dur - 20) && s.durationSeconds <= (dur + 20) &&
                s.distanceMeters >= (distM - 80) && s.distanceMeters <= (distM + 80)
            }
            if let existing = try? context.fetch(FetchDescriptor<RunningSession>(predicate: pred)).first {
                // Ya existía (probablemente creado al recibir el fichero del Watch) → solo enriquecemos la ruta
                if existing.routePolyline == nil,
                   let poly = await fetchRoutePolyline(for: wk, healthStore: healthStore) {
                    existing.routePolyline = poly
                }
                continue // ❗ No insertes otro
            }

            // Ruta (si Apple Health la tiene)
            let poly = await fetchRoutePolyline(for: wk, healthStore: healthStore)

            let run = RunningSession(
                date: wk.startDate,
                durationSeconds: Int(wk.duration.rounded()),
                distanceMeters: distM,
                notes: "Imported from Apple Health",
                routePolyline: poly
            )
            run.totalPoints = PointsCalculator.score(running: run, settings: settings)
            context.insert(run)
            inserted += 1
        }

        try context.save()
        if inserted > 0 { print("[HK][SAVE+ROUTE] inserted: \(inserted)") }
        return inserted
    }


}

extension HealthKitImportService {
    /// Lee métricas (pace/elev/HR) para una sesión existente usando HealthKit.
    /// No modifica tu BD; es solo lectura para pintar la UI.
    static func fetchRunMetrics(for session: RunningSession,
                                healthStore: HKHealthStore = HKHealthStore()) async throws -> RunMetrics? {
        
        print("[HealthKitImportService]fetchRunMetrics is called")

        // 1) Buscar el HKWorkout que mejor coincide (por fecha y distancia)
        guard let workout = try await findMatchingWorkout(for: session, healthStore: healthStore) else {
            return nil
        }

        // 2) Ruta con timestamps (CLLocation)
        let locations = try await fetchRouteLocations(for: workout, healthStore: healthStore)

        // 3) Calcular pace (splits + serie) y elevación
        let (splits, paceSeries) = computePace(locations: locations, duration: session.durationSeconds)
        let (elevSeries, ascent) = computeElevation(locations: locations)

        // 4) HR del workout
        let (hrSeries, avg, max) = try await fetchHeartRateSeries(for: workout, healthStore: healthStore)

        return RunMetrics(splits: splits,
                          paceSeries: paceSeries,
                          elevationSeries: elevSeries,
                          totalAscent: ascent,
                          heartRateSeries: hrSeries,
                          avgHR: avg, maxHR: max)
    }

    // MARK: - Helpers

    private static func findMatchingWorkout(for s: RunningSession,
                                            healthStore: HKHealthStore) async throws -> HKWorkout? {
        print("[HealthKitImportService]findMatchingWorkout is called")
        let type = HKObjectType.workoutType()
        // ventana ±30 min respecto al inicio
        let start = s.date.addingTimeInterval(-30*60)
        let end   = s.date.addingTimeInterval(TimeInterval(s.durationSeconds) + 30*60)
        let pDate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let pRun  = HKQuery.predicateForWorkouts(with: .running)
        let pred  = NSCompoundPredicate(andPredicateWithSubpredicates: [pDate, pRun])

        let sort  = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: sort) {
                _, res, err in
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: (res as? [HKWorkout]) ?? [])
            }
            healthStore.execute(q)
        }

        // elegir el más cercano en distancia y hora
        let targetM = s.distanceMeters
        func score(_ wk: HKWorkout) -> Double {
            let d = wk.totalDistance?.doubleValue(for: .meter()) ?? 0
            let dt = abs(wk.startDate.timeIntervalSince(s.date))
            let distScore = abs(d - targetM)
            return distScore + dt * 0.1
        }
        return workouts.min(by: { score($0) < score($1) })
    }

    private static func fetchRouteLocations(for workout: HKWorkout,
                                            healthStore: HKHealthStore) async throws -> [CLLocation] {
        
        print("[HealthKitImportService]fetchRouteLocations is called")
        // Antes: guard let routeType = HKObjectType.seriesType(forIdentifier: .workoutRoute) else { return [] }
        let routeType = HKSeriesType.workoutRoute()   // ✅ correcto

        let pred = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: routeType,
                                  predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                let routes = (samples as? [HKWorkoutRoute]) ?? []
                if routes.isEmpty { cont.resume(returning: []); return }

                var all: [CLLocation] = []
                let group = DispatchGroup()

                for r in routes {
                    group.enter()
                    let rq = HKWorkoutRouteQuery(route: r) { _, locs, done, err in
                        if let err = err { print("route error:", err) }
                        if let locs = locs { all.append(contentsOf: locs) }
                        if done { group.leave() }
                    }
                    healthStore.execute(rq)
                }

                group.notify(queue: .global(qos: .userInitiated)) {
                    cont.resume(returning: all.sorted { $0.timestamp < $1.timestamp })
                }
            }
            healthStore.execute(q) // ← recuerda ejecutar también esta query
        }
    }

    private static func fetchHeartRateSeries(for workout: HKWorkout,
                                             healthStore: HKHealthStore) async throws
    -> ([(time: TimeInterval, bpm: Double)], Double?, Double?) {
        
        print("[HealthKitImportService]fetchHeartRateSeries is called")

        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return ([], nil, nil) }
        let pred = HKQuery.predicateForObjects(from: workout)
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) {
                _, res, err in
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }

        guard !samples.isEmpty else { return ([], nil, nil) }

        let start = workout.startDate
        var series: [(TimeInterval, Double)] = []
        series.reserveCapacity(samples.count)

        var sum = 0.0, maxB = 0.0
        for s in samples {
            let bpm = s.quantity.doubleValue(for: unit)
            sum += bpm; maxB = max(maxB, bpm)
            series.append((s.startDate.timeIntervalSince(start), bpm))
        }
        let avg = sum / Double(samples.count)
        return (series.sorted { $0.0 < $1.0 }, avg, maxB)
    }

    // Pace y elevación a partir de CLLocation
    private static func computePace(
        locations: [CLLocation],
        duration: Int
    ) -> (splits: [RunMetrics.Split], series: [(time: TimeInterval, secPerKm: Double)]) {

        guard locations.count >= 2 else { return ([], []) }

        // Serie de ritmo: muestreo cada 100m con ventana acumulada
        let step: Double = 100.0 // metros
        var windowDist: Double = 0
        var windowTime: TimeInterval = 0

        var cumDist: Double = 0
        var cumTime: TimeInterval = 0

        var paceSeries: [(TimeInterval, Double)] = []
        paceSeries.reserveCapacity(Int((locations.last!.distance(from: locations.first!)) / step) + 1)

        // Splits por kilómetro (duración de cada km)
        var splits: [RunMetrics.Split] = []
        var nextSplit: Double = 1000.0
        var lastSplitTime: TimeInterval = 0

        for i in 1..<locations.count {
            let prev = locations[i-1]
            let curr = locations[i]

            let d  = max(curr.distance(from: prev), 0)                          // metros
            let dt = max(curr.timestamp.timeIntervalSince(prev.timestamp), 0)   // segundos
            guard d > 0, dt > 0 else { continue }

            cumDist += d
            cumTime += dt

            // ---- Ventana acumulada para serie de ritmo (cada 100 m) ----
            windowDist += d
            windowTime += dt
            while windowDist >= step {
                // Tiempo proporcional contenido en los primeros 100 m de la ventana
                let frac = step / windowDist
                let tSlice = windowTime * frac
                let elapsedFromStart = cumTime - (windowTime - tSlice)

                // Ritmo medio de la ventana (s/km)
                let secPerKm = (windowTime / windowDist) * 1000.0
                paceSeries.append((elapsedFromStart, secPerKm))

                // Consumimos esos 100 m de la ventana
                windowDist -= step
                windowTime -= tSlice
            }

            // ---- Splits por kilómetro (interpolando el cruce del umbral) ----
            while cumDist >= nextSplit {
                // ¿qué fracción del tramo actual cae dentro del km que se cierra?
                let over = cumDist - nextSplit
                let fracInSegment = (d > 0) ? (1.0 - over / d) : 1.0

                // Tiempo exacto cuando cruzamos el km
                let timeAtThreshold = cumTime - dt * (1.0 - fracInSegment)

                // Duración del km acabado = t(umbral) - t(umbral anterior)
                let splitSeconds = timeAtThreshold - lastSplitTime
                splits.append(.init(km: Int(nextSplit / 1000.0), seconds: splitSeconds))

                lastSplitTime = timeAtThreshold
                nextSplit += 1000.0
            }
        }

        // Si no se emitió nada (rutas muy cortas), añade un punto final medio
        if paceSeries.isEmpty, cumDist > 0 {
            let secPerKm = (cumTime / cumDist) * 1000.0
            paceSeries.append((cumTime, secPerKm))
        }

        return (splits, paceSeries)
    }


    private static func computeElevation(locations: [CLLocation])
    -> (series: [(TimeInterval, Double)], ascent: Double) {
        guard let first = locations.first else { return ([], 0) }
        let start = first.timestamp
        var series: [(TimeInterval, Double)] = []
        series.reserveCapacity(locations.count)
        var ascent: Double = 0
        let noise: Double = 1.5 // metros para filtrar ruido

        for i in 0..<locations.count {
            let h = locations[i].altitude
            series.append((locations[i].timestamp.timeIntervalSince(start), h))
            if i > 0 {
                let gain = h - locations[i-1].altitude
                if gain > noise { ascent += gain }
            }
        }
        return (series, ascent)
    }
}

extension HealthKitImportService {
    struct BackfillResult {
        var scanned: Int = 0
        var updated: Int = 0
        var notFoundInHK: Int = 0
        var noRouteInHK: Int = 0
    }

    /// Busca en tu BD las RunningSession sin routePolyline, intenta localizar
    /// el HKWorkout correspondiente y, si HealthKit tiene ruta, la guarda.
    /// Al finalizar devuelve un pequeño resumen.
    @MainActor
    static func backfillMissingRoutes(
        context: ModelContext,
        limit: Int? = nil,
        healthStore: HKHealthStore = HKHealthStore()
    ) async throws -> BackfillResult {
        
        print("[HealthKitImportService]backfillMissingRoutes is called")

        // 1) Buscar runs sin ruta
        let pred = #Predicate<RunningSession> { $0.routePolyline == nil || $0.routePolyline == "" }
        var desc = FetchDescriptor<RunningSession>(predicate: pred,
                                                   sortBy: [SortDescriptor(\.date, order: .forward)])
        if let limit { desc.fetchLimit = limit }
        let runs = (try? context.fetch(desc)) ?? []

        var result = BackfillResult(scanned: runs.count)

        guard !runs.isEmpty else { return result }

        // 2) Para cada run, localizar HKWorkout y leer polyline
        for run in runs {
            do {
                // Usa tu helper existente para casar la sesión local con un HKWorkout
                // (definido en el mismo fichero) 👇
                guard let workout = try await findMatchingWorkout(for: run, healthStore: healthStore) else {
                    result.notFoundInHK += 1
                    continue
                }

                // Lee la ruta de ese workout y encódala (helper existente) 👇
                if let poly = await fetchRoutePolyline(for: workout, healthStore: healthStore) {
                    run.routePolyline = poly
                    result.updated += 1
                } else {
                    result.noRouteInHK += 1
                }

            } catch {
                // Si hay error puntual con un workout, sigue con el resto
                print("[Backfill] error for run \(run.id):", error.localizedDescription)
            }
        }

        try context.save()
        print("[Backfill] scanned=\(result.scanned) updated=\(result.updated) notFound=\(result.notFoundInHK) noRoute=\(result.noRouteInHK)")
        return result
    }
}
