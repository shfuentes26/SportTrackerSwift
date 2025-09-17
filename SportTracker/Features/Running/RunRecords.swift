import Foundation

// Tipo de badge con ranking
public enum RecordBadgeKind: Equatable {
    case absolute(rank: Int, bucketKm: Double)                 // BR
    case yearly(rank: Int, year: Int, bucketKm: Double)        // YY (25)
}

public struct RecordBadgeModel: Identifiable, Equatable {
    public let id = UUID()
    public let kind: RecordBadgeKind
}

// Motor de récords de Running
public enum RunRecords {
    private static let bucketsKm: [Double] = [1.0, 3.0, 5.0, 10.0, 21.0975, 42.195]

    /// Regla: asigna el **mayor bucket** <= distancia del run (en km).
    /// Ej: 5.5 -> 5K, 10.3 -> 10K, 0.95 -> nil (no llega a 1K).
    public static func assignBucketKm(for km: Double, minFactor: Double = 1.0) -> Double? {
        let candidates = bucketsKm.filter { km >= $0 * minFactor }
        return candidates.max()
    }

    /// Devuelve los badges (top-N) para un run, comparando solo con runs del mismo bucket asignado.
    /// - Parameters:
    ///   - top: máximo rango a mostrar (3 = oro/plata/bronce)
    ///   - minFactor: umbral para alcanzar el bucket (1.0 = exactamente la regla “≤ distancia”)
    ///   - preferAbsoluteOverYear: si true, oculta el anual si ya hay oro absoluto (evitar doble dorado)
    public static func badges(
        for run: RunningSession,
        among runs: [RunningSession],
        top: Int = 3,
        minFactor: Double = 1.0,
        preferAbsoluteOverYear: Bool = false
    ) -> [RecordBadgeModel] {

        let km = run.distanceMeters / 1000.0
        guard let bucket = assignBucketKm(for: km, minFactor: minFactor) else { return [] }

        // Misma asignación de bucket para todos
        let sameBucket = runs.filter { r in
            let rkm = r.distanceMeters / 1000.0
            return assignBucketKm(for: rkm, minFactor: minFactor) == bucket
        }

        // Ranking por: mejor pace -> menor duración -> fecha más reciente
        let sortedAbs = sameBucket.sorted {
            let p0 = paceSecPerKm($0), p1 = paceSecPerKm($1)
            if p0 != p1 { return p0 < p1 }
            if $0.durationSeconds != $1.durationSeconds { return $0.durationSeconds < $1.durationSeconds }
            return $0.date > $1.date
        }

        var result: [RecordBadgeModel] = []

        // Absoluto
        if let idx = sortedAbs.firstIndex(where: { $0.id == run.id }) {
            let rank = idx + 1
            if rank <= top {
                result.append(.init(kind: .absolute(rank: rank, bucketKm: bucket)))
            }
        }

        // Anual (año del propio run)
        let year = Calendar.current.component(.year, from: run.date)
        let sameYear = sortedAbs.filter { Calendar.current.component(.year, from: $0.date) == year }
        if let idxY = sameYear.firstIndex(where: { $0.id == run.id }) {
            let rankY = idxY + 1
            if rankY <= top {
                // ¿ocultamos el anual si ya es oro absoluto?
                if preferAbsoluteOverYear,
                   result.contains(where: {
                       if case .absolute(let r, _) = $0.kind { return r == 1 }
                       return false
                   }), rankY == 1 {
                    // no añadir el anual dorado
                } else {
                    result.append(.init(kind: .yearly(rank: rankY, year: year, bucketKm: bucket)))
                }
            }
        }

        return result
    }

    // MARK: - helpers privados
    private static func paceSecPerKm(_ r: RunningSession) -> Double {
        let km = max(r.distanceMeters / 1000.0, 0.001)
        return Double(r.durationSeconds) / km
    }
}
