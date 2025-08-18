import SwiftData
import Foundation

@MainActor
protocol RunningRepository {
    func list() throws -> [RunningSession]
    func save(_ run: RunningSession) throws
    func delete(_ run: RunningSession) throws
}

@MainActor
final class SwiftDataRunningRepository: RunningRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func list() throws -> [RunningSession] {
        let fd = FetchDescriptor<RunningSession>(
            sortBy: [SortDescriptor(\RunningSession.date, order: .reverse)]
        )
        return try context.fetch(fd)
    }

    func save(_ run: RunningSession) throws {
        if run.persistentModelID == nil { context.insert(run) }
        try context.save()
    }

    func delete(_ run: RunningSession) throws {
        context.delete(run)
        try context.save()
    }
}
