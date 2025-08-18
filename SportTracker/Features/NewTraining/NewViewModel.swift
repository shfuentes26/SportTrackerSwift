//
//  NewViewModel.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/18/25.
//

import Observation
import SwiftData
import Foundation

@MainActor @Observable
final class NewViewModel {
    private let context: ModelContext
    private let runningRepo: RunningRepository
    private let strengthRepo: StrengthRepository
    init(context: ModelContext,
         runningRepo: RunningRepository,
         strengthRepo: StrengthRepository) {
        self.context = context
        self.runningRepo = runningRepo
        self.strengthRepo = strengthRepo
    }

    func saveRunning(date: Date, km: Double, seconds: Int, notes: String?) throws {
        let run = RunningSession(date: date, durationSeconds: seconds,
                                 distanceMeters: km*1000, notes: notes)
        let s = try fetchOrCreateSettings()
        run.totalPoints = PointsCalculator.score(running: run, settings: s)
        context.insert(run)
        try context.save()
    }
    // idem saveGym(...)
    private func fetchOrCreateSettings() throws -> Settings {
        if let s = try context.fetch(FetchDescriptor<Settings>()).first { return s }
        let s = Settings(); context.insert(s); return s
    }
}
