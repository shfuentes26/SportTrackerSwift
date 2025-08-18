import SwiftData
import Foundation

@MainActor
protocol StrengthRepository {
    func list() throws -> [StrengthSession]
    func save(_ session: StrengthSession) throws
    func delete(_ session: StrengthSession) throws
}

@MainActor
final class SwiftDataStrengthRepository: StrengthRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func list() throws -> [StrengthSession] {
        let fd = FetchDescriptor<StrengthSession>(
            sortBy: [SortDescriptor(\StrengthSession.date, order: .reverse)]
        )
        return try context.fetch(fd)
    }

    func save(_ session: StrengthSession) throws {
        if session.persistentModelID == nil { context.insert(session) }
        try context.save()
    }

    func delete(_ session: StrengthSession) throws {
        context.delete(session)
        try context.save()
    }
}
