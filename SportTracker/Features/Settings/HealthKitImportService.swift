import Foundation
import SwiftData
import HealthKit

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
}
