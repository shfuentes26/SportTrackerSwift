import Observation
import SwiftData

@MainActor @Observable
final class RunningViewModel {
    var runs: [RunningSession] = []
    private let repo: RunningRepository
    private let context: ModelContext

    init(repo: RunningRepository, context: ModelContext) {
        self.repo = repo
        self.context = context
    }

    func load() {
        runs = (try? repo.list()) ?? []
    }

    func delete(_ r: RunningSession) {
        try? repo.delete(r)
        load()
    }

    func recalcPoints(for r: RunningSession) {
        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        if settings.persistentModelID == nil { context.insert(settings) }
        r.totalPoints = PointsCalculator.score(running: r, settings: settings)
        try? repo.save(r)
        load()
    }
}
