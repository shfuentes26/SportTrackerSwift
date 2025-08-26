//
//  RunningRecordsView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/20/25.
//
// RunningRecordsView.swift
import SwiftUI
import SwiftData

/// Distancias soportadas para récords
enum RecordDistance: String, CaseIterable, Identifiable {
    case k1  = "1K"
    case k3  = "3K"
    case k5  = "5K"
    case k10 = "10K"
    case half = "Half Marathon"
    case marathon = "Marathon"

    var id: String { rawValue }

    /// Distancia objetivo en kilómetros
    var targetKm: Double {
        switch self {
        case .k1: return 1.0
        case .k3: return 3.0
        case .k5: return 5.0
        case .k10: return 10.0
        case .half: return 21.0975
        case .marathon: return 42.195
        }
    }
}

struct RunningRecordsView: View {
    let runs: [RunningSession]
    let useMiles: Bool
    
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("All-time Records")
                    .font(.headline)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(RecordDistance.allCases) { dist in
                        RecordCard(distance: dist,
                                   record: bestRecord(for: dist, from: runs))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }
}

// Record helpers (pueden ir en el mismo archivo)

struct RunRecord {
    let totalTime: TimeInterval     // seconds
    let pacePerKm: TimeInterval     // seconds per km
    let date: Date
}

/// Devuelve el mejor tiempo para la distancia `dist` usando las sesiones guardadas.
/// Reglas:
/// - Solo se consideran runs con distancia dentro de ±3% de la distancia objetivo.
/// - Entre candidatos, gana el tiempo total más bajo.
/// - Si no hay candidatos, devuelve `nil` → "No record yet".
func bestRecord(for dist: RecordDistance, from runs: [RunningSession]) -> RunRecord? {
    let targetKm = dist.targetKm

    // Candidatos: runs válidos que cubren al menos la distancia objetivo
    let candidates = runs.filter { r in
        r.durationSeconds > 0 && (r.distanceMeters / 1000.0) >= targetKm
    }
    guard !candidates.isEmpty else { return nil }

    // Elige el mejor por "tiempo estimado a la distancia objetivo"
    guard let best = candidates.min(by: { a, b in
        let kmA = max(a.distanceMeters / 1000.0, 0.001)
        let kmB = max(b.distanceMeters / 1000.0, 0.001)
        let paceA = Double(a.durationSeconds) / kmA        // s/km
        let paceB = Double(b.durationSeconds) / kmB        // s/km
        return (paceA * targetKm) < (paceB * targetKm)
    }) else {
        return nil
    }

    let km = max(best.distanceMeters / 1000.0, 0.001)
    let pacePerKm = TimeInterval(Double(best.durationSeconds) / km) // s/km
    let estimatedTimeAtTarget = pacePerKm * targetKm                 // s

    return RunRecord(totalTime: estimatedTimeAtTarget,
                     pacePerKm: pacePerKm,
                     date: best.date)
}


/// Formateadores
func formatDuration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded())
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%02d:%02d", m, sec)
}

func formatPace(_ secondsPerKm: TimeInterval) -> String {
    let s = Int(secondsPerKm.rounded())
    let m = s / 60
    let sec = s % 60
    return String(format: "%d:%02d", m, sec)
}

struct RecordCard: View {
    let distance: RecordDistance
    let record: RunRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // título / chip
            Text(distance.rawValue)
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 2)

            if let r = record {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("🏆")
                    Text(formatDuration(r.totalTime))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }

                Text("Pace \(formatPace(r.pacePerKm))/km")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(r.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                // opcional: CTA
                // Text("View runs ›")
                //     .font(.footnote.weight(.semibold))
                //     .foregroundColor(.accentColor)
            } else {
                Spacer(minLength: 4)
                Text("No record yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

