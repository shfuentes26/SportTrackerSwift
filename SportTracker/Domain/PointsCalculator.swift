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
        let km = max(running.distanceKm, 0)
        let minutes = Double(running.durationSeconds) / 60.0

        // Pace score: faster than baseline => >1, slower => <1 (min clamp)
        let pace = running.paceSecondsPerKm
        let baseline = max(settings.runningPaceBaselineSecPerKm, 1)
        let paceRatio = baseline / max(pace, 1) // if pace = baseline -> 1.0

        // Base actual (tu lógica existente)
        let base = (km * settings.runningDistanceFactor)
                 + (minutes * settings.runningTimeFactor)
                 + (paceRatio * settings.runningPaceFactor)

        // NEW: bonus de resistencia con crecimiento superlineal en distancia
        let endurance = pow(km, settings.runningEnduranceExponent) * settings.runningEnduranceFactor

        return max(base + endurance, 0)
    }


    static func score(strength session: StrengthSession, settings: Settings) -> Double {
        var total: Double = 0

        // Parámetros del suelo
        let MIN_WEIGHTED_MULTIPLIER = 1.10
        let MIN_WEIGHTED_BONUS = 0.80

        for set in session.sets {
            let ex = set.exercise

            // --- CON PESO ---
            if ex.isWeighted, let wRaw = set.weightKg, wRaw > 0 {
                let repsD = Double(set.reps)
                let targetWkg = weightedIntermediateTarget(for: ex) // e.g., squat -> 130

                // 🚫 No conviertas: weightKg ya está en KG
                let wKG = wRaw
                let volume = repsD * wKG

                // Baseline "como si fuera sin peso"
                let bodyweightBaseline: Double = {
                    if let target = bodyweightIntermediateTarget(for: ex) {
                        let raw = 100.0 * (repsD / target)
                        return min(max(raw, 0.0), 150.0)
                    } else {
                        return repsD * settings.gymRepsFactor
                    }
                }()

                // Puntos con peso (benchmark o fallback lineal)
                let weightedPoints: Double = {
                    if let t = targetWkg {
                        let targetVolume = max(t * 30.0, 1.0) // 100 pts en t*30
                        let raw = 100.0 * (volume / targetVolume)
                        return min(max(raw, 0.0), 200.0)
                    } else {
                        return volume * settings.gymWeightedFactor
                    }
                }()

                // Suelo: +10% sobre baseline y bonus proporcional a w/t
                var minAllowed = bodyweightBaseline * MIN_WEIGHTED_MULTIPLIER
                var wRatioLogged: Double = .nan
                var bonusFactorLogged: Double = 1.0
                if let t = targetWkg {
                    let wRatio = max(min(wKG / t, 1.0), 0.0)   // 0..1 con KG
                    wRatioLogged = wRatio
                    let bonusFactor = 1.0 + (MIN_WEIGHTED_BONUS * wRatio)
                    bonusFactorLogged = bonusFactor
                    minAllowed = max(minAllowed, bodyweightBaseline * bonusFactor)
                }

                // 🔎 LOGS
                /*print("PoinstsCalculator - weightedIntermediateTarget - ejercicio comprobado", ex.name.lowercased())
                print("PoinstsCalculator - score - reps =", Int(repsD), "wRaw =", wRaw, "→ wKG =", wKG)
                print("PoinstsCalculator - score - targetWkg =", String(describing: targetWkg))*/
                if let t = targetWkg {
                    let targetVolume = t * 30.0
                    print("PoinstsCalculator - score - volume =", volume, "targetVolume =", targetVolume)
                    print("PoinstsCalculator - score - ratio", wRatioLogged)
                    print("PoinstsCalculator - score - bonusFactor", bonusFactorLogged)
                }
                /*print("PoinstsCalculator - score - minAllowed", minAllowed)
                print("PoinstsCalculator - score - weightedPoints", weightedPoints)
                */
                let sum = max(weightedPoints, minAllowed)
                total += sum
                //print("PoinstsCalculator - score - total", total)
                continue
            }

            // --- SIN PESO (bodyweight) ---
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
    
    private static func weightedIntermediateTarget(for ex: Exercise) -> Double? {
        
        //print("PoinstsCalculator - weightedIntermediateTarget - ejercicio comprobado", ex.name.lowercased())
        switch ex.name.lowercased() {
        // Chest / Back
        case "bench press", "press banca": return 98
        case "machine chest fly", "machine fly", "aperturas máquina": return 87
        case "lat pulldown", "jalón al pecho": return 82
        case "shoulder shrug", "barbell shrug", "encogimientos trapecio": return 131

        // Arms (mancuernas: valores por mancuerna)
        case "dumbbell curl", "curl mancuerna": return 23
        case "tricep pushdown", "triceps pushdown", "extensión tríceps polea": return 57
        case "side lateral raise", "lateral raise", "elevaciones laterales": return 15
        case "hammer curl", "curl martillo": return 23
        case "overhead triceps extension", "dumbbell triceps extension",
             "extensión tríceps por encima de la cabeza": return 23

        // Legs
        case "squat", "sentadilla": return 130
        case "lunge", "dumbbell lunge", "zancadas": return 30   // por mancuerna
        case "deadlift", "peso muerto": return 152
        case "leg extension", "extensión de cuádriceps": return 96
        case "calf raises", "seated calf raise", "standing calf raise", "gemelos": return 134
        case "romanian deadlift", "peso muerto rumano": return 120
        case "leg press", "sled leg press", "prensa de piernas": return 226

        default:
            return nil
        }
    }


}
