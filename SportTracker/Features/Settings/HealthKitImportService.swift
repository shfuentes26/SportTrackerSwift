import Foundation
import SwiftData
import HealthKit
import CoreLocation

enum HealthKitImportService {

    /// Guarda en SwiftData solo entrenamientos de running (HKWorkout ya filtrado por tu manager).
    /// Devuelve cuántos se insertaron.
    static func saveToLocal(_ workouts: [HealthKitManager.ImportedWorkout],
                            context: ModelContext) throws -> Int {
        var inserted = 0

        for wk in workouts {
            // Solo running con distancia válida
            guard wk.activity == .running, let distM = wk.distanceMeters, distM > 0 else { continue }

            let run = RunningSession(
                date: wk.start,
                durationSeconds: Int(wk.durationSec.rounded()),
                distanceMeters: distM,
                notes: "Imported from Apple Health"
            )
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

        for wk in workouts {
            guard wk.workoutActivityType == .running else { continue }
            let distM = wk.totalDistance?.doubleValue(for: .meter()) ?? 0
            guard distM > 0 else { continue }

            // Ruta (si Apple Health la tiene)
            let poly = await fetchRoutePolyline(for: wk, healthStore: healthStore)

            let run = RunningSession(
                date: wk.startDate,
                durationSeconds: Int(wk.duration.rounded()),
                distanceMeters: distM,
                notes: "Imported from Apple Health",
                routePolyline: poly
            )
            context.insert(run)
            inserted += 1
        }

        try context.save()
        if inserted > 0 { print("[HK][SAVE+ROUTE] inserted: \(inserted)") }
        return inserted
    }


}
