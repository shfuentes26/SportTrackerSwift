//
//  HealthKitImportService.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//

import Foundation
import SwiftData

enum HealthKitImportService {

    /// Guarda en SwiftData solo entrenamientos de running.
    /// Devuelve cuántos se insertaron.
    static func saveToLocal(_ workouts: [HealthKitManager.ImportedWorkout],
                            context: ModelContext) throws -> Int {

        var inserted = 0

        for wk in workouts {
            // Solo running
            guard wk.activity == .running,
                  let distM = wk.distanceMeters, distM > 0 else { continue }

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
        return inserted
    }
    
    private func mapWorkout(_ wk: HealthKitManager.ImportedWorkout) -> RunningSession? {
        guard wk.activity == .running,
              let distM = wk.distanceMeters, distM > 0 else { return nil }

        return RunningSession(
            date: wk.start,
            durationSeconds: Int(wk.durationSec.rounded()),
            distanceMeters: distM,
            notes: "Imported from Apple Health"
        )
    }
}



