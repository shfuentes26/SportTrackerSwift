//
//  PointsRecalculator.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/10/25.
//
import Foundation
import SwiftData

@MainActor
enum PointsRecalculator {
    static func recalculateAll(context: ModelContext) throws -> (gym: Int, run: Int) {
        // 1) Asegura que exista Settings
        let sFD = FetchDescriptor<Settings>()
        let settings = try context.fetch(sFD).first ?? {
            let s = Settings()
            context.insert(s)
            return s
        }()

        // 2) Running
        var runTouched = 0
        let rFD = FetchDescriptor<RunningSession>()
        let runs = try context.fetch(rFD)
        for session in runs {
            let newPoints = PointsCalculator.score(running: session, settings: settings)
            if session.totalPoints != newPoints {
                session.totalPoints = newPoints
                session.updatedAt = Date()
                runTouched += 1
            }
        }

        // 3) Gym (Strength)
        var gymTouched = 0
        let gFD = FetchDescriptor<StrengthSession>()
        let gyms = try context.fetch(gFD)
        for session in gyms {
            let newPoints = PointsCalculator.score(strength: session, settings: settings)
            if session.totalPoints != newPoints {
                session.totalPoints = newPoints
                session.updatedAt = Date()
                gymTouched += 1
            }
        }

        try context.save()
        return (gymTouched, runTouched)
    }
}

