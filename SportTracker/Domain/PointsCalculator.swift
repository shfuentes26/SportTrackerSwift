//
//  PointsCalculator.swift
//  SportTracker
//
//  Scoring utilities based on user's rules.
//  Running -> distance, time, and pace (lower pace = more points)
//  Gym -> bodyweight: more reps; weighted: more weight & reps
//

import Foundation
import SwiftData

struct PointsCalculator {

    static func score(running: RunningSession, settings: Settings) -> Double {
        let km = running.distanceKm
        let minutes = Double(running.durationSeconds) / 60.0

        // Pace score: faster than baseline => >1, slower => <1 (min clamp)
        let pace = running.paceSecondsPerKm
        let baseline = max(settings.runningPaceBaselineSecPerKm, 1)
        let paceRatio = baseline / max(pace, 1) // if pace = baseline -> 1.0

        let points = (km * settings.runningDistanceFactor)
                   + (minutes * settings.runningTimeFactor)
                   + (paceRatio * settings.runningPaceFactor)

        return max(points, 0)
    }

    static func score(strength session: StrengthSession, settings: Settings) -> Double {
        var total: Double = 0

       // for set in session.sets {
       //     let ex = set.exercise
        for set in (session.sets ?? []) {
            guard let ex = set.exercise else { continue }

        
            if ex.isWeighted, let w = set.weightKg, w > 0 {
                // Igual que ahora para ejercicios con carga
                total += (Double(set.reps) * w) * settings.gymWeightedFactor
                continue
            }

            // --- Bodyweight: usar benchmark "Intermediate" = 100 pts ---
            if let target = bodyweightIntermediateTarget(for: ex) {
                // Si tu UI guarda tiempo (p. ej. plank), usa 'set.durationSec' aquí
                let reps = Double(set.reps) // para ejercicios por rep
                let raw = 100.0 * (reps / target)
                total += min(raw, 150.0)    // cap opcional
            } else {
                // Fallback si no tenemos benchmark para ese ejercicio
                total += Double(set.reps) * settings.gymRepsFactor
            }
        }

        return max(total, 0)
    }

    // Mapa de benchmarks "Intermediate" (reps -> 100 pts)
    private static func bodyweightIntermediateTarget(for ex: Exercise) -> Double? {
        switch ex.name.lowercased() {
        case "pull-ups", "pull ups":              return 14    // Strength Level
        case "push ups", "push-ups":              return 41    // Strength Level (male table)
        case "hanging leg raise":                 return 18    // Strength Level
        case "crunches":                          return 55    // Strength Level
        case "russian twist":                     return 45    // Strength Level
        // Si usas plank por duración y guardas segundos en el set, cambia a duración:
        // case "plank": return 90
        default: return nil
        }
    }

}
