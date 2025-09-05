import Foundation
import SwiftData

struct PointsCalculator {

    static func score(running: RunningSession, settings: Settings) -> Double {
        let km = running.distanceKm
        let minutes = Double(running.durationSeconds) / 60.0

        let pace = running.paceSecondsPerKm
        let baseline = max(settings.runningPaceBaselineSecPerKm, 1)
        let paceRatio = baseline / max(pace, 1)

        let points = (km * settings.runningDistanceFactor)
                   + (minutes * settings.runningTimeFactor)
                   + (paceRatio * settings.runningPaceFactor)

        return max(points, 0)
    }

    static func score(strength session: StrengthSession, settings: Settings) -> Double {
            var total: Double = 0

            // sets ahora es NO opcional (vía @Transient)
            for set in session.sets {
                // exercise también es NO opcional (vía @Transient)
                let ex = set.exercise

                if ex.isWeighted, let w = set.weightKg, w > 0 {
                    total += (Double(set.reps) * w) * settings.gymWeightedFactor
                    continue
                }

                if let target = bodyweightIntermediateTarget(for: ex) {
                    let reps = Double(set.reps)
                    let raw = 100.0 * (reps / target)
                    total += min(raw, 150.0)
                } else {
                    total += Double(set.reps) * settings.gymRepsFactor
                }
            }

            return max(total, 0)
        }

    private static func bodyweightIntermediateTarget(for ex: Exercise) -> Double? {
        switch ex.name.lowercased() {
        case "pull-ups", "pull ups": return 14
        case "push ups", "push-ups": return 41
        case "hanging leg raise":    return 18
        case "crunches":             return 55
        case "russian twist":        return 45
        // case "plank": return 90 // si usas duración
        default: return nil
        }
    }
}
