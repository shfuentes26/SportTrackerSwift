import Observation
import Foundation
import SwiftData

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

    // MARK: - Validations
    func validateDistance(_ text: String) -> Double? {
        let t = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let km = Double(t), km > 0 else { return nil }
        return km
    }

    func validateDuration(h: String, m: String, s: String) -> Int? {
        let hh = Int(h) ?? 0
        let mm = Int(m) ?? 0
        let ss = Int(s) ?? 0
        let total = hh*3600 + mm*60 + ss
        return total > 0 ? total : nil
    }

    // MARK: - Running
    func saveRunning(date: Date, km: Double, seconds: Int, notes: String?) throws {
        let run = RunningSession(date: date,
                                 durationSeconds: seconds,
                                 distanceMeters: km * 1000.0,
                                 notes: notes)
        let settings = try fetchOrCreateSettings()
        run.totalPoints = PointsCalculator.score(running: run, settings: settings)

        context.insert(run)                // new object
        try runningRepo.save(run)          // persist
    }

    // MARK: - Gym
    struct NewTrainingSet {
        let exercise: Exercise
        let order: Int
        let reps: Int
        let weightKg: Double?
    }

    func saveGym(date: Date, notes: String?, sets: [NewTrainingSet]) throws {
        let session = StrengthSession(date: date, notes: notes)

        for s in sets.sorted(by: { $0.order < $1.order }) {
            let set = StrengthSet(exercise: s.exercise,
                                  order: s.order,
                                  reps: s.reps,
                                  weightKg: s.weightKg)
            set.session = session
            session.sets.append(set)
        }

        let settings = try fetchOrCreateSettings()
        session.totalPoints = PointsCalculator.score(strength: session, settings: settings)

        context.insert(session)            // new object
        try strengthRepo.save(session)     // persist
    }

    // MARK: - Helpers
    private func fetchOrCreateSettings() throws -> Settings {
        if let s = try context.fetch(FetchDescriptor<Settings>()).first {
            return s
        } else {
            let s = Settings()
            context.insert(s)
            return s
        }
    }
}
