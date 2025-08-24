//
//  ExercisesFormView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//
// Features/Settings/ExerciseFormView.swift
import SwiftUI
import SwiftData
import PhotosUI

struct ExerciseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var exercise: Exercise?          // nil = crear nuevo
    var onSave: () -> Void

    @State private var name: String = ""
    @State private var group: MuscleGroup = .chestBack
    @State private var weighted: Bool = false
    @State private var notes: String = ""

    init(exercise: Exercise?, onSave: @escaping () -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _name     = State(initialValue: exercise?.name ?? "")
        _group    = State(initialValue: exercise?.muscleGroup ?? .chestBack)
        _weighted = State(initialValue: exercise?.isWeighted ?? false)
        _notes    = State(initialValue: exercise?.notes ?? "")
    }
    
    private func systemIcon(for group: MuscleGroup, weighted: Bool) -> String {
        // Mapeo simple y robusto (SF Symbols estándar)
        switch group {
        case .core:
            return "figure.strengthtraining.functional"
        case .chestBack, .arms, .legs:
            return weighted ? "dumbbell" : "figure.strengthtraining.functional"
        @unknown default:
            return "dumbbell"
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Image(systemName: systemIcon(for: group, weighted: weighted))
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 48, weight: .semibold))
                        .frame(width: 96, height: 96)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            Section("Basics") {
                TextField("Name", text: $name)
                Picker("Category", selection: $group) {
                    Text("Core").tag(MuscleGroup.core)
                    Text("Chest/Back").tag(MuscleGroup.chestBack)
                    Text("Arms").tag(MuscleGroup.arms)
                    Text("Legs").tag(MuscleGroup.legs)
                }
                Toggle("Weighted (kg)", isOn: $weighted)
            }
            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
            }
        }
        .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let ex = exercise {
                        ex.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        ex.muscleGroup = group
                        ex.isWeighted = weighted
                        ex.notes = notes
                    } else {
                        let ex = Exercise(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            muscleGroup: group,
                            isWeighted: weighted,
                            isCustom: true,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        context.insert(ex)
                    }
                    try? context.save()
                    onSave()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
