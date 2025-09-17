import Foundation
import SwiftData
import HealthKit
import CoreLocation

enum HealthKitImportService {
    
    
    @MainActor
    static func saveBodyMassSamplesToLocal(
        _ samples: [HKQuantitySample],
        context: ModelContext
    ) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        var inserted = 0
        let kgUnit = HKUnit.gramUnit(with: .kilo)
        let weightRaw = MeasurementKind.weight.rawValue  // 👈 evita usar el enum dentro del #Predicate

        for s in samples {
            let kg = s.quantity.doubleValue(for: kgUnit)
            guard kg > 0 else { continue }

            // Ventana para dedupe
            let minDate = s.startDate.addingTimeInterval(-30 * 60)
            let maxDate = s.startDate.addingTimeInterval(+30 * 60)

            // 👇 Predicado sencillo: solo tipo + rango de fecha
            var fd = FetchDescriptor<BodyMeasurement>(
                predicate: #Predicate {
                    $0.kindRaw == weightRaw &&
                    $0.date >= minDate && $0.date <= maxDate
                }
            )
            fd.fetchLimit = 5  // pequeño límite por seguridad

            let nearby = try context.fetch(fd)

            // Deduplicado por valor ±0.2 kg en memoria (evita el predicado complejo)
            let isDuplicate = nearby.contains { abs($0.value - kg) <= 0.2 }
            if isDuplicate { continue }

            // Inserta
            context.insert(BodyMeasurement(
                date: s.startDate,
                kind: .weight,
                value: kg,
                note: "Imported from Apple Health"
            ))
            inserted += 1
        }

        try context.save()
        return inserted
    }

    /// Guarda en SwiftData solo entrenamientos de running (HKWorkout ya filtrado por tu manager).
    /// Devuelve cuántos se insertaron.
    static func saveToLocal(_ workouts: [HealthKitManager.ImportedWorkout],
                            context: ModelContext) throws -> Int {
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

        // 1) Buscar el HKWorkout que mejor coincide (por fecha y distancia)
        guard let workout = try await findMatchingWorkout(for: session, healthStore: healthStore) else {
            print("[HK][Metrics] ❌ No matching workout for run at \(session.date) dist=\(Int(session.distanceMeters))m dur=\(session.durationSeconds)s")
                
            return nil
        }
        // Splits exactos desde los distance samples de HealthKit
        let distSplits = await calcKmSplitsFromDistanceSamples(for: workout, healthStore: healthStore)
        
        Task {

            await debugPrintKmSplits_FromDistanceSamples(for: workout, healthStore: healthStore)
        }
            

        // 2) Ruta con timestamps (CLLocation)
        let locations = try await fetchRouteLocations(for: workout, healthStore: healthStore)
        print("[HK][Metrics] route.locations=\(locations.count)")
        if locations.isEmpty {
            print("[HK][Metrics] ⚠️ Workout has no route locations (route permission denied or source app didn’t write route)")
        }

        // 3) Pace (serie) y elevación desde RUTA
        var (_routeSplits, paceSeries) = computePace(locations: locations, duration: session.durationSeconds)
        let (elevSeries, ascent) = computeElevation(locations: locations)

        // 👉 Splits definitivos: usa los de distance samples si existen; si no, los de la ruta
        let splits = distSplits.isEmpty ? _routeSplits : distSplits
        debugPrintKmSplits(splits,
                           label: distSplits.isEmpty ? "per-km from ROUTE (raw)"
                                                     : "per-km from HKQuantitySample(distance)",
                           expectedTotal: TimeInterval(session.durationSeconds))

        // Solo si la ruta no nos da una serie de pace útil, hacemos fallback de serie usando distance samples
        if paceSeries.isEmpty {
            let distSamples = try await fetchDistanceSamples(for: workout, healthStore: healthStore)
            let (_, ser2) = computePaceFromDistanceSamples(samples: distSamples,
                                                           duration: session.durationSeconds,
                                                           start: workout.startDate)
            if !ser2.isEmpty { paceSeries = ser2 }
        }

        print("[HK][Metrics] splits.count=\(splits.count) paceSeries.count=\(paceSeries.count) elev.count=\(elevSeries.count) ascent=\(Int(ascent))m")

        // 4) HR del workout
        let (hrSeries, avg, max) = try await fetchHeartRateSeries(for: workout, healthStore: healthStore)
        print("[HK][Metrics] HR points=\(hrSeries.count) avg=\(avg.map{Int($0)}) max=\(max.map{Int($0)})")

        return RunMetrics(splits: splits,
                          paceSeries: paceSeries,
                          elevationSeries: elevSeries,
                          totalAscent: ascent,
                          heartRateSeries: hrSeries,
                          avgHR: avg, maxHR: max)

    }

    // MARK: - Helpers
    // MARK: - DEBUG: imprimir splits por km desde la serie de distancia de HealthKit

    private static func dbgHMS(_ t: TimeInterval) -> String {
        let ti = Int(round(t))
        let h = ti / 3600, m = (ti % 3600) / 60, s = ti % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
    
    // Splits por km a partir de HKWorkoutRoute + pausas reales.
    // Seguro para compilar: solo usa APIs que ya empleas en este archivo.
    // Splits por km a partir de HKWorkoutRoute + pausas reales (sin reescalados)
    static func debugPrintKmSplitsFromRouteUsingEvents(for workout: HKWorkout,
                                                       healthStore: HKHealthStore) async {
        func mmss(_ t: TimeInterval) -> String {
            let ti = Int(round(t)); return String(format: "%d:%02d", ti/60, ti%60)
        }

        let pred = HKQuery.predicateForObjects(from: workout)

        // 1) Rutas del workout (API correcta y compatible)
        let routeType: HKSeriesType = HKSeriesType.workoutRoute()
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: routeType,
                                  predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, results, _ in   // <-- 3 params
                let arr = (results as? [HKWorkoutRoute])?.sorted { $0.startDate < $1.startDate } ?? []
                cont.resume(returning: arr)
            }
            healthStore.execute(q)
        }
        guard !routes.isEmpty else { print("[HK][ROUTE] no routes for workout"); return }

        // 2) Puntos de localización (timestamp + coord)
        var locs: [CLLocation] = []
        let group = DispatchGroup()
        for r in routes {
            group.enter()
            let rq = HKWorkoutRouteQuery(route: r) { _, batch, done, _ in
                if let batch = batch { locs.append(contentsOf: batch) }
                if done { group.leave() }
            }
            healthStore.execute(rq)
        }
        group.wait()
        locs.sort { $0.timestamp < $1.timestamp }
        guard locs.count >= 2 else { print("[HK][ROUTE] not enough locations"); return }

        // 3) Línea de tiempo (t, distancia acumulada)
        var timeline: [(t: Date, d: Double)] = [(locs.first!.timestamp, 0)]
        var cumD: Double = 0
        for i in 1..<locs.count {
            let seg = max(locs[i].distance(from: locs[i-1]), 0)
            cumD += seg
            timeline.append((locs[i].timestamp, cumD))
        }
        if (timeline.last?.t ?? workout.startDate) < workout.endDate {
            timeline.append((workout.endDate, cumD))
        }

        // 4) Pausas reales (pause/resume)
        let events = (workout.workoutEvents ?? []).sorted { $0.date < $1.date }
        var pauses: [(Date, Date)] = []
        var open: Date? = nil
        for e in events {
            switch e.type {
            case .pause:  open = e.date
            case .resume: if let s = open { pauses.append((s, e.date)); open = nil }
            default: break
            }
        }
        if let s = open { pauses.append((s, workout.endDate)) }

        func pausedOverlap(from a: Date, to b: Date) -> TimeInterval {
            var s: TimeInterval = 0
            for (p0, p1) in pauses {
                let start = max(a, p0), end = min(b, p1)
                if end > start { s += end.timeIntervalSince(start) }
            }
            return s
        }

        // 5) Cruce exacto de cada km + split con "moving time"
        var splits: [TimeInterval] = []
        var lastSplitTime = workout.startDate
        var nextKm: Double = 1000
        let maxD = timeline.last!.d

        var i = 1
        while nextKm <= maxD, i < timeline.count {
            while i < timeline.count, timeline[i].d < nextKm { i += 1 }
            guard i < timeline.count else { break }

            let (t0, d0) = timeline[i-1]
            let (t1, d1) = timeline[i]
            let denom = max(d1 - d0, 0.000001)
            let ratio = (nextKm - d0) / denom
            let ts = t0.addingTimeInterval(t1.timeIntervalSince(t0) * ratio)

            // Split = tiempo entre marcas menos pausas en ese intervalo
            let raw = ts.timeIntervalSince(lastSplitTime)
            let paused = pausedOverlap(from: lastSplitTime, to: ts)
            let splitSec = max(raw - paused, 0)
            splits.append(splitSec)

            print(String(format: "[HK][ROUTE] km=%.0f between d0=%.1f@%@  d1=%.1f@%@  ratio=%.3f  split=%@",
                         nextKm/1000.0, d0, t0.description, d1, t1.description, ratio, mmss(splitSec)))

            lastSplitTime = ts
            nextKm += 1000
        }

        // 6) Logs finales
        var cumul: TimeInterval = 0
        for (k, s) in splits.enumerated() {
            cumul += s
            print(String(format: "[HK][Splits][ROUTE] km=%d  split=%@  cumul=%@",
                         k+1, mmss(s), mmss(cumul)))
        }
        let totalRaw = workout.endDate.timeIntervalSince(workout.startDate)
        let totalPaused = pausedOverlap(from: workout.startDate, to: workout.endDate)
        print(String(format: "[HK][Totals][ROUTE] distance=%.0fm  moving=%@  elapsed=%@  splits=%d  route.points=%d",
                     maxD, mmss(max(totalRaw - totalPaused, 0)), mmss(totalRaw), splits.count, locs.count))
    }

    
    //Gemin
    
    // ❶ Devuelve splits por km calculados SOLO con HKQuantitySample(distanceWalkingRunning)
    static func calcKmSplitsFromDistanceSamples(for workout: HKWorkout,
                                                healthStore: HKHealthStore) async -> [RunMetrics.Split] {
        // Pedimos TODOS los samples de distancia de ese workout, ordenados cronológicamente
        guard let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return [] }
        let pred = HKQuery.predicateForObjects(from: workout)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: distType,
                                  predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: sort) { _, res, _ in
                cont.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }
        guard !samples.isEmpty else { return [] }

        // ❷ Procesamos acumulando distancia y tiempo; cuando cruzamos 1000 m, emitimos un split
        var splits: [RunMetrics.Split] = []
        var cumD: Double = 0.0                         // metros desde el inicio
        var lastSplitDate: Date = workout.startDate    // fecha del último km emitido
        var nextThreshold: Double = 1000.0             // siguiente km a cruzar

        for s in samples {
            let d  = s.quantity.doubleValue(for: .meter())          // metros del sample
            let dt = max(s.endDate.timeIntervalSince(s.startDate), 0)
            guard d > 0, dt > 0 else { continue }

            let startD = cumD
            let endD   = cumD + d

            // Puede cruzar varios kms dentro del mismo sample
            while nextThreshold <= endD {
                // fracción (0..1) del sample donde se cruza el km
                let ratio = (nextThreshold - startD) / max(d, 0.000001)
                // instante exacto de cruce dentro del sample
                let splitDate = s.startDate.addingTimeInterval(dt * ratio)
                // segundos del split = tiempo entre esta marca y la anterior
                let seconds = splitDate.timeIntervalSince(lastSplitDate)

                splits.append(.init(km: Int(nextThreshold / 1000.0), seconds: seconds))
                lastSplitDate = splitDate
                nextThreshold += 1000.0
            }

            cumD = endD
        }

        return splits
    }

    // ❸ Versión de depuración que imprime los splits (usa tu helper debugPrintKmSplits)
    static func debugPrintKmSplits_FromDistanceSamples(for workout: HKWorkout,
                                                       healthStore: HKHealthStore) async {
        let splits = await calcKmSplitsFromDistanceSamples(for: workout, healthStore: healthStore)
        debugPrintKmSplits(splits,
                           label: "per-km from HKQuantitySample(distance)",
                           expectedTotal: workout.duration)  // compara con duración real del workout
    }

    
    

    /// Imprime la serie cruda de distancia y los splits por km calculados *solo* con la serie.
    /// No modifica ningún dato: es puramente de logs.
    static func debugPrintKmSplitsFromDistanceSeries(for workout: HKWorkout,
                                                     healthStore: HKHealthStore) async {
        guard let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }

        // 1) Traemos los samples de distancia asociados a este workout
        let pred = HKQuery.predicateForObjects(from: workout)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: distType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                let arr = (res as? [HKQuantitySample])?.sorted { $0.startDate < $1.startDate } ?? []
                cont.resume(returning: arr)
            }
            healthStore.execute(q)
        }

        guard !samples.isEmpty else {
            print("[HK][Series] no distance samples for workout")
            return
        }

        print("[HK][Series] ---- raw distance SERIES & per-km splits ----")

        // Acumuladores globales
        var cumD: Double = 0                // metros acumulados
        var cumT: TimeInterval = 0          // segundos acumulados desde workout.start
        var lastDateGlobal: Date? = nil

        var kmSplits: [TimeInterval] = []
        var nextSplit: Double = 1000.0
        var lastSplitTime: TimeInterval = 0

        // Usamos un DispatchGroup para esperar a todas las series
        let group = DispatchGroup()

        for s in samples {
            group.enter()

            // Handler correcto: (query, quantity, date, done, error)
            let seriesQuery = HKQuantitySeriesSampleQuery(sample: s) { _, quantity, date, done, error in
                if let error = error {
                    print("[HK][Series] error: \(error.localizedDescription)")
                }

                if let q = quantity, let pointDate = date {
                    // Distancia registrada en este "punto" de la serie (metros)
                    let meters = q.doubleValue(for: .meter())

                    // Tiempo transcurrido desde el punto anterior de la *serie global*
                    let prevDate = lastDateGlobal ?? workout.startDate
                    let dt = max(pointDate.timeIntervalSince(prevDate), 0)

                    cumD += meters
                    cumT += dt
                    lastDateGlobal = pointDate

                    // Log de tramo crudo
                    print(String(format: "[HK][Series] +%.0fm in %@  (cumul: %.0fm, %@)",
                                 meters, dbgHMS(dt), cumD, dbgHMS(cumT)))

                    // Interpola cruces de 1 km
                    var remainMeters = meters
                    while cumD >= nextSplit, remainMeters > 0 {
                        // cuánto nos pasamos del múltiplo dentro de este punto
                        let over = cumD - nextSplit
                        let fracInPoint = (remainMeters > 0) ? (1.0 - over / remainMeters) : 1.0
                        let timeAtThreshold = cumT - dt * (1.0 - fracInPoint)

                        let splitSeconds = timeAtThreshold - lastSplitTime
                        kmSplits.append(splitSeconds)

                        lastSplitTime = timeAtThreshold
                        nextSplit += 1000.0

                        // reducimos "remainMeters" para no contar dos veces
                        remainMeters -= (remainMeters - over)
                        if remainMeters < 0 { remainMeters = 0 }
                    }
                }

                if done {
                    group.leave()
                }
            }

            healthStore.execute(seriesQuery)
        }

        // Espera a terminar TODAS las series (solo para logs)
        group.wait()

        // Imprime los splits por km
        var cumul: TimeInterval = 0
        for (i, sec) in kmSplits.enumerated() {
            cumul += sec
            print(String(format: "[HK][Splits] km=%2d  split=%@  cumul=%@",
                         i + 1, dbgHMS(sec), dbgHMS(cumul)))
        }

        // Totales
        print(String(format: "[HK][Splits] total distance ~= %.0fm  total time ~= %@",
                     cumD, dbgHMS(cumT)))
    }


    // 1) Lee "distanceWalkingRunning" como SERIE (no el sample agregado).
    //    Imprime fecha, delta-distancia y delta-tiempo de cada punto.
    static func debugPrintDistanceSeries(for workout: HKWorkout,
                                         healthStore: HKHealthStore) async {
        guard let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }

        // 1) Traer los samples que pertenecen al workout
        let pred = HKQuery.predicateForObjects(from: workout)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: distType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                cont.resume(returning: (res as? [HKQuantitySample])?.sorted { $0.startDate < $1.startDate } ?? [])
            }
            healthStore.execute(q)
        }
        guard !samples.isEmpty else { print("[HK][Series] no distance samples"); return }

        print("[HK][Series] ---- raw distance SERIES points ----")
        var cumulD: Double = 0
        var cumulT: TimeInterval = 0
        var lastDate: Date? = nil

        // 2) Enumerar la SERIE interna de cada sample
        let group = DispatchGroup()
        for s in samples {
            group.enter()
            let seriesQuery = HKQuantitySeriesSampleQuery(sample: s) { _, quantity, date, done, error in
                if let error = error {
                    print("[HK][Series] error: \(error.localizedDescription)")
                }
                if let q = quantity, let pointDate = date {
                    let meters = q.doubleValue(for: .meter())
                    let prevDate = lastDate ?? s.startDate
                    let dt = max(pointDate.timeIntervalSince(prevDate), 0)

                    cumulD += meters
                    cumulT += dt
                    lastDate = pointDate

                    print(String(format: "[HK][Series] +%.0fm in %@  (cumul: %.0fm, %@)",
                                 meters, hms(dt), cumulD, hms(cumulT)))
                }
                if done { group.leave() }
            }
            healthStore.execute(seriesQuery)
        }
        group.wait()

        print(String(format: "[HK][Series] total: %.0fm in %@", cumulD, hms(cumulT)))
    }


    
    // === DEBUG helpers para imprimir splits en formato humano ===
    private static func debugHMS(_ t: TimeInterval) -> String {
        let ti = Int(round(t))
        let h = ti / 3600, m = (ti % 3600) / 60, s = ti % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private static func debugPrintKmSplits(_ splits: [RunMetrics.Split],
                                           label: String,
                                           expectedTotal: TimeInterval? = nil) {
        print("[HK][Splits] ---- \(label) ----")
        var cumul: TimeInterval = 0
        for s in splits {
            cumul += s.seconds
            print(String(format: "[HK][Splits] km=%2d  split=%@  cumul=%@",
                         s.km, debugHMS(s.seconds), debugHMS(cumul)))
        }
        if let exp = expectedTotal {
            print(String(format: "[HK][Splits] total=%@  expected=%@",
                         debugHMS(cumul), debugHMS(exp)))
        } else {
            print(String(format: "[HK][Splits] total=%@", debugHMS(cumul)))
        }
    }


    // Lee y vuelca muestras de distancia del workout en la consola
    // REEMPLAZA COMPLETO ESTE MÉTODO
    static func debugPrintDistanceSamples(for workout: HKWorkout,
                                          healthStore: HKHealthStore) async {
        func fmt(_ t: TimeInterval) -> String {
            let m = Int(t) / 60, s = Int(t) % 60
            return String(format: "%02d:%02d", m, s)
        }

        guard let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }

        // 1) Trae los samples de distancia de ESTE workout
        let pred = HKQuery.predicateForObjects(from: workout)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: distType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                let arr = (res as? [HKQuantitySample])?.sorted { $0.startDate < $1.startDate } ?? []
                cont.resume(returning: arr)
            }
            healthStore.execute(q)
        }

        guard !samples.isEmpty else {
            print("[HK][Series] no distance samples")
            return
        }

        print("[HK][Series] ---- distance series + per-km splits (MOVING) ----")

        // Acumulados
        var cumDistance: Double = 0.0                 // m
        var elapsedT: TimeInterval = 0.0              // s (incluye pausas)
        var movingT: TimeInterval  = 0.0              // s (solo cuando hay avance)
        var lastDate: Date? = nil

        // Splits
        var kmSplits: [TimeInterval] = []
        var nextKm: Double = 1000.0
        var lastSplitMovingT: TimeInterval = 0.0

        let MIN_MOVE_M = 0.5   // ignora jitter (<0.5 m)

        let group = DispatchGroup()

        for s in samples {
            group.enter()
            let seriesQ = HKQuantitySeriesSampleQuery(sample: s) { _, quantity, date, done, error in
                if let error = error { print("[HK][Series] error: \(error.localizedDescription)") }

                if let q = quantity, let pointDate = date {
                    let deltaMeters = q.doubleValue(for: .meter())
                    let prevDate = lastDate ?? workout.startDate
                    let deltaT = max(pointDate.timeIntervalSince(prevDate), 0)

                    // Tiempo total (incluye pausas)
                    elapsedT += deltaT

                    if deltaMeters > MIN_MOVE_M {
                        // --- TIEMPO EN MOVIMIENTO: usamos este para los splits ---
                        let startD = cumDistance
                        let startMovingT = movingT

                        // Puede cruzar varios km en el mismo segmento
                        while nextKm <= startD + deltaMeters {
                            let ratio = (nextKm - startD) / deltaMeters         // 0..1
                            let timeAtSplit = startMovingT + ratio * deltaT     // SOLO moving time
                            kmSplits.append(timeAtSplit - lastSplitMovingT)
                            lastSplitMovingT = timeAtSplit
                            nextKm += 1000.0
                        }

                        // Avanza acumulados de movimiento y distancia
                        movingT += deltaT
                        cumDistance += deltaMeters
                    }
                    // Si no hay avance, consideramos pausa: movingT y distancia no cambian

                    lastDate = pointDate
                }

                if done { group.leave() }
            }
            healthStore.execute(seriesQ)
        }

        group.wait()

        // Logs finales
        var cumul: TimeInterval = 0
        for (i, sec) in kmSplits.enumerated() {
            cumul += sec
            print(String(format: "[HK][Splits][SERIES] km=%d  split=%@  cumul=%@",
                         i + 1, fmt(sec), fmt(cumul)))
        }

        print(String(format: "[HK][Totals] distance=%.0fm  moving=%@  elapsed=%@  splits=%d",
                     cumDistance, fmt(movingT), fmt(elapsedT), kmSplits.count))
    }
    
    // Calcula e imprime splits por km usando la serie de distancia + pausas reales del workout.
    // No modifica BD; solo logs. Seguro para compilar con el fichero actual.
    static func debugPrintKmSplitsUsingEvents(for workout: HKWorkout,
                                              healthStore: HKHealthStore) async {
        // formatter local para evitar depender de helpers externos
        func fmt(_ t: TimeInterval) -> String {
            let ti = Int(round(t))
            let m = (ti % 3600) / 60, s = ti % 60
            return String(format: "%d:%02d", m, s)
        }

        guard let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }

        // 1) Construir línea de tiempo (fecha, distancia acumulada)
        let pred = HKQuery.predicateForObjects(from: workout)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: distType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                cont.resume(returning: (res as? [HKQuantitySample])?.sorted { $0.startDate < $1.startDate } ?? [])
            }
            healthStore.execute(q)
        }
        guard !samples.isEmpty else {
            print("[HK][Series] no distance samples for workout"); return
        }

        var timeline: [(t: Date, d: Double)] = [(workout.startDate, 0.0)]
        var cumD: Double = 0
        var lastDate = workout.startDate

        let group = DispatchGroup()
        for s in samples {
            group.enter()
            let seriesQ = HKQuantitySeriesSampleQuery(sample: s) { _, quantity, date, done, _ in
                if let q = quantity, let t = date {
                    cumD += q.doubleValue(for: .meter())
                    lastDate = t
                    timeline.append((t, cumD))
                }
                if done { group.leave() }
            }
            healthStore.execute(seriesQ)
        }
        group.wait()
        if timeline.last?.t ?? workout.startDate < workout.endDate {
            timeline.append((workout.endDate, cumD))
        }

        // 2) Pausas reales (HKWorkoutEvent) del workout
        let events = (workout.workoutEvents ?? []).sorted { $0.date < $1.date }
        var pauseIntervals: [(Date, Date)] = []
        var openPause: Date? = nil
        for e in events {
            switch e.type {
            case .pause:  openPause = e.date
            case .resume:
                if let ps = openPause { pauseIntervals.append((ps, e.date)); openPause = nil }
            default: break
            }
        }
        if let ps = openPause { pauseIntervals.append((ps, workout.endDate)) } // por si faltó resume

        func pausedSeconds(until t: Date) -> TimeInterval {
            var s: TimeInterval = 0
            for (a, b) in pauseIntervals {
                let start = max(a, workout.startDate)
                let end   = min(b, t)
                if end > start { s += end.timeIntervalSince(start) }
            }
            return s
        }
        func movingTime(at t: Date) -> TimeInterval {
            let elapsed = t.timeIntervalSince(workout.startDate)
            return max(elapsed - pausedSeconds(until: t), 0)
        }

        // 3) Interpolar cruce exacto de cada km y calcular split con moving time
        var splits: [TimeInterval] = []
        var lastMoveAtSplit: TimeInterval = 0
        var target: Double = 1000
        let maxD = timeline.last?.d ?? 0

        var i = 1
        while target <= maxD, i < timeline.count {
            while i < timeline.count, timeline[i].d < target { i += 1 }
            guard i < timeline.count else { break }

            let (t0, d0) = timeline[i - 1]
            let (t1, d1) = timeline[i]
            let denom = max(d1 - d0, 0.000001)
            let ratio = (target - d0) / denom
            let ts = t0.addingTimeInterval(t1.timeIntervalSince(t0) * ratio)

            let moveAt = movingTime(at: ts)
            splits.append(moveAt - lastMoveAtSplit)
            lastMoveAtSplit = moveAt

            target += 1000
        }

        // 4) Logs
        var cumul: TimeInterval = 0
        for (idx, sp) in splits.enumerated() {
            cumul += sp
            print(String(format: "[HK][Splits][EV] km=%d  split=%@  cumul=%@",
                         idx + 1, fmt(sp), fmt(cumul)))
        }
        let totalMoving = movingTime(at: timeline.last!.t)
        print(String(format: "[HK][Totals][EV] distance=%.0fm  moving=%@  elapsed=%@",
                     maxD, fmt(totalMoving), fmt(workout.endDate.timeIntervalSince(workout.startDate))))
    }



    // Helper de formato (si no lo tienes ya en el archivo)
    private static func hms(_ t: TimeInterval) -> String {
        let ti = Int(round(t))
        let h = ti / 3600, m = (ti % 3600) / 60, s = ti % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    
    

    private static func findMatchingWorkout(for s: RunningSession,
                                            healthStore: HKHealthStore) async throws -> HKWorkout? {
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
    // Pace y elevación a partir de CLLocation
    private static func computePace(
        locations: [CLLocation],
        duration: Int
    ) -> (splits: [RunMetrics.Split], series: [(time: TimeInterval, secPerKm: Double)]) {

        guard locations.count >= 2 else { return ([], []) }

        // ---------- PASO 0: distancia total (para ritmo medio global) ----------
        var totalDistMeters: Double = 0
        for i in 1..<locations.count {
            totalDistMeters += max(locations[i].distance(from: locations[i-1]), 0)
        }
        // Evita división por cero
        totalDistMeters = max(totalDistMeters, 1)
        let avgSecPerMeterGlobal = TimeInterval(duration) / totalDistMeters   // "rescate" si el dt del tramo es basura

        // ---------- Serie (100m) + Splits por km ----------
        let step: Double = 100.0 // metros
        var windowDist: Double = 0
        var windowTime: TimeInterval = 0

        var cumDist: Double = 0
        var cumTime: TimeInterval = 0

        var paceSeries: [(TimeInterval, Double)] = []   // (time, secPerKm)
        paceSeries.reserveCapacity(Int(totalDistMeters / step) + 1)

        var splits: [RunMetrics.Split] = []
        var nextSplit: Double = 1000.0
        var lastSplitTime: TimeInterval = 0

        for i in 1..<locations.count {
            let prev = locations[i-1]
            let curr = locations[i]

            let dRaw  = max(curr.distance(from: prev), 0)                         // metros
            var dtRaw = max(curr.timestamp.timeIntervalSince(prev.timestamp), 0)  // segundos

            // --- SANEO DE TIEMPO DE TRAMO ---
            // Si el ritmo implícito es físicamente imposible (< 2:30 /km), o dt=0,
            // sustituimos dt por el tiempo "razonable" a ritmo medio global.
            if dRaw > 0 {
                let paceSecPerKmRaw = (dtRaw / dRaw) * 1000.0
                if dtRaw == 0 || paceSecPerKmRaw < 150.0 { // 150s/km == 2:30 /km
                    dtRaw = dRaw * avgSecPerMeterGlobal
                    // Descomenta si quieres ver cuándo sanea:
                    // print("[HK][Fix] clamped dt at segment \(i)  d=\(Int(dRaw))m")
                }
            }
            let d = dRaw
            let dt = dtRaw
            guard d > 0, dt > 0 else { continue }

            cumDist += d
            cumTime += dt

            // ---- Serie de ritmo (cada 100 m, usando ventana deslizante) ----
            windowDist += d
            windowTime += dt
            while windowDist >= step {
                let frac = step / windowDist                 // proporción de esos 100 m en la ventana
                let tSlice = windowTime * frac               // tiempo correspondiente a esos 100 m
                let elapsedFromStart = cumTime - (windowTime - tSlice)

                let secPerKm = (windowTime / windowDist) * 1000.0
                paceSeries.append((elapsedFromStart, secPerKm))

                windowDist -= step
                windowTime -= tSlice
            }

            // ---- Splits por kilómetro (interpolando el cruce exacto) ----
            while cumDist >= nextSplit {
                let over = cumDist - nextSplit
                let fracInSegment = (d > 0) ? (1.0 - over / d) : 1.0
                let timeAtThreshold = cumTime - dt * (1.0 - fracInSegment)

                let splitSeconds = timeAtThreshold - lastSplitTime
                splits.append(.init(km: Int(nextSplit / 1000.0), seconds: splitSeconds))

                lastSplitTime = timeAtThreshold
                nextSplit += 1000.0
            }
        }

        // Si no hubo muestreo, emite un punto medio
        if paceSeries.isEmpty, cumDist > 0 {
            let secPerKm = (cumTime / cumDist) * 1000.0
            paceSeries.append((cumTime, secPerKm))
        }

        // ---------- Reescalado final si el total no cuadra con 'duration' ----------
        let totalComputed = cumTime
        let actual = TimeInterval(duration)
        if totalComputed > 0 {
            let diff = abs(totalComputed - actual) / max(actual, 1)
            if diff > 0.20 { // >20% de desvío ⇒ normaliza todo
                let scale = actual / totalComputed
                print("[HK][Pace] ⚠️ Rescaling time by ×\(scale) (cum=\(totalComputed)s, actual=\(actual)s)")
                splits = splits.map { .init(km: $0.km, seconds: $0.seconds * scale) }
                paceSeries = paceSeries.map { ($0.0 * scale, $0.1 * scale) }
            }
        }

        let totalSplits = splits.reduce(0) { $0 + $1.seconds }
        print("[HK][Pace] splits.count=\(splits.count) totalSplits=\(Int(totalSplits))s (expected ≈ \(duration)s)")

        // Devuelve con labels (son compatibles con el tipo)
        return (splits, paceSeries.map { (time: $0.0, secPerKm: $0.1) })
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
    
    // Devuelve la desviación estándar de los segundos por km (para detectar splits "planos")
    private static func stdDevSeconds(_ splits: [RunMetrics.Split]) -> Double {
        guard splits.count >= 2 else { return .infinity }
        let xs = splits.map { $0.seconds }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let v = xs.reduce(0) { $0 + pow($1 - mean, 2) } / Double(xs.count)
        return sqrt(v)
    }

    // Lee muestras de distancia del propio workout
    private static func fetchDistanceSamples(for workout: HKWorkout,
                                             healthStore: HKHealthStore) async throws -> [HKQuantitySample] {
        guard let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return [] }
        let pred = HKQuery.predicateForObjects(from: workout)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: distType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, err in
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }
        return samples.sorted { $0.startDate < $1.startDate }
    }

    // Construye splits/serie a partir de **muestras de distancia** (no usa ruta)
    private static func computePaceFromDistanceSamples(samples: [HKQuantitySample],
                                                       duration: Int,
                                                       start: Date) -> (splits: [RunMetrics.Split], series: [(time: TimeInterval, secPerKm: Double)]) {
        guard !samples.isEmpty else { return ([], []) }

        var splits: [RunMetrics.Split] = []
        var paceSeries: [(TimeInterval, Double)] = []

        var cumDist: Double = 0        // metros
        var cumTime: TimeInterval = 0  // segundos
        var lastSplitTime: TimeInterval = 0
        var nextSplit: Double = 1000.0

        // ventana 100m para la serie
        let step: Double = 100.0
        var windowDist: Double = 0
        var windowTime: TimeInterval = 0

        for s in samples {
            let d = s.quantity.doubleValue(for: HKUnit.meter())
            let dt = max(s.endDate.timeIntervalSince(s.startDate), 0)
            guard d > 0, dt > 0 else { continue }

            cumDist += d
            cumTime += dt

            // Serie cada 100m
            windowDist += d
            windowTime += dt
            while windowDist >= step {
                let frac = step / windowDist
                let tSlice = windowTime * frac
                let elapsed = cumTime - (windowTime - tSlice)
                let secPerKm = (windowTime / windowDist) * 1000.0
                paceSeries.append((elapsed, secPerKm))
                windowDist -= step
                windowTime -= tSlice
            }

            // Splits por km (interpolando cruce exacto)
            while cumDist >= nextSplit {
                let over = cumDist - nextSplit
                let fracInSeg = (d > 0) ? (1.0 - over / d) : 1.0
                let timeAtThreshold = cumTime - dt * (1.0 - fracInSeg)
                let splitSeconds = timeAtThreshold - lastSplitTime
                splits.append(.init(km: Int(nextSplit / 1000.0), seconds: splitSeconds))
                lastSplitTime = timeAtThreshold
                nextSplit += 1000.0
            }
        }

        // Reescala a la duración real si hay deriva
        let total = cumTime
        let actual = TimeInterval(duration)
        if total > 0 {
            let diff = abs(total - actual) / max(actual, 1)
            if diff > 0.2 {
                let scale = actual / total
                splits = splits.map { .init(km: $0.km, seconds: $0.seconds * scale) }
                paceSeries = paceSeries.map { ($0.0 * scale, $0.1 * scale) }
                print("[HK][Pace][DIST] rescaled ×\(scale)")
            }
        }

        return (splits, paceSeries.map { (time: $0.0, secPerKm: $0.1) })
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
