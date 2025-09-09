import Foundation
import SwiftUI

final class ExercisesStore: ObservableObject {
    @Published var exercises: [ExerciseItem] = [] { didSet { save() } }
    private let fileURL: URL

    init(filename: String = "exercises.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent(filename)
        load()
        if exercises.isEmpty {
            exercises = [
                ExerciseItem(name: "Push Ups", category: .chestBack),
                ExerciseItem(name: "Dumbbell Row", category: .chestBack, usesVariableWeight: true),
                ExerciseItem(name: "Plank", category: .core)
            ]
        }
    }

    func add(_ ex: ExerciseItem)    { exercises.append(ex) }
    func update(_ ex: ExerciseItem) { if let i = exercises.firstIndex(where: {$0.id==ex.id}) { exercises[i] = ex } }
    func delete(at offsets: IndexSet) { exercises.remove(atOffsets: offsets) }

    private func load() { if let d = try? Data(contentsOf: fileURL),
                           let arr = try? JSONDecoder().decode([ExerciseItem].self, from: d) { exercises = arr } }
    private func save() { if let d = try? JSONEncoder().encode(exercises) { try? d.write(to: fileURL, options: [.atomic]) } }
}
