import Observation
import SwiftData

@MainActor @Observable
final class GymViewModel {
    var sessions: [StrengthSession] = []
    private let repo: StrengthRepository
    private let context: ModelContext

    init(repo: StrengthRepository, context: ModelContext) {
        self.repo = repo
        self.context = context
    }

    func load() {
        sessions = (try? repo.list()) ?? []
    }

    func delete(_ s: StrengthSession) {
        try? repo.delete(s)
        load()
    }

    func recalcPoints(for s: StrengthSession) {
        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        if settings.persistentModelID == nil { context.insert(settings) }
        s.totalPoints = PointsCalculator.score(strength: s, settings: settings)
        try? repo.save(s)
        load()
    }
}
