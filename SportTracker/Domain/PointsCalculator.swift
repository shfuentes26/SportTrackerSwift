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
        for set in session.sets {
            if let w = set.weightKg, w > 0 {
                total += (Double(set.reps) * w) * settings.gymWeightedFactor
            } else {
                total += Double(set.reps) * settings.gymRepsFactor
            }
        }
        return max(total, 0)
    }
}
