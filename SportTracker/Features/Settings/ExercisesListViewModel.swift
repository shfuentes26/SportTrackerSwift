import Foundation
import SwiftUI
import SwiftData

@MainActor
final class ExercisesListViewModel: ObservableObject {
    @Published var search: String = ""
    @Published var selected: MuscleGroup? = nil

    func filteredExercises(from allExercises: [Exercise]) -> [Exercise] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return allExercises.filter { ex in
            let categoryMatches = selected == nil || ex.muscleGroup == selected
            let nameMatches = trimmed.isEmpty || ex.name.localizedCaseInsensitiveContains(trimmed)
            return categoryMatches && nameMatches
        }
    }

    // 🔎 Helpers de diagnóstico
    static func slug(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
         .lowercased()
    }

    static func logDuplicates(context: ModelContext, tag: String = "ExercisesListView") {
        do {
            let all = try context.fetch(FetchDescriptor<Exercise>())
            var groups: [String: [Exercise]] = [:]
            for e in all { groups[slug(e.name), default: []].append(e) }
            let dups = groups.filter { $0.value.count > 1 }
            if dups.isEmpty {
                print("[DBG][\(tag)] no duplicates ✅ (total=\(all.count))")
            } else {
                let pretty = dups
                    .sorted { $0.value.count > $1.value.count }
                    .map { "\($0.key)×\($0.value.count)" }
                    .joined(separator: ", ")
                print("[DBG][\(tag)] duplicates → \(pretty) (total=\(all.count))")
            }
        } catch {
            print("[DBG][\(tag)] fetch error:", String(describing: error))
        }
    }
}
