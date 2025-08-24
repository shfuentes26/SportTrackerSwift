//
//  ExercisesListView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//

// Features/Settings/ExercisesListView.swift
import SwiftUI
import SwiftData

struct ExercisesListView: View {
    @Environment(\.modelContext) private var context

    // SwiftData: todos los ejercicios ordenados por nombre
    @Query(sort: [SortDescriptor(\Exercise.name, order: .forward)])
    private var allExercises: [Exercise]

    @State private var selected: MuscleGroup? = nil     // nil = All
    @State private var search: String = ""
    // por estas:
    @State private var creating = false
    @State private var editing: Exercise? = nil

    // Rompemos la expresión en bloques simples para ayudar al type-checker
    private var filtered: [Exercise] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sel = selected {
            if q.isEmpty {
                return allExercises.filter { (ex: Exercise) in ex.muscleGroup == sel }
            } else {
                return allExercises.filter { (ex: Exercise) in
                    ex.muscleGroup == sel && ex.name.localizedCaseInsensitiveContains(q)
                }
            }
        } else {
            if q.isEmpty { return allExercises }
            return allExercises.filter { (ex: Exercise) in
                ex.name.localizedCaseInsensitiveContains(q)
            }
        }
    }

    var body: some View {
        List {
            let items = filtered  // otra pista al compilador
            if items.isEmpty {
                ContentUnavailableView(
                    "No exercises yet",
                    systemImage: "dumbbell",
                    description: Text("Add your first exercise with the + button.")
                )
            } else {
                ForEach(items) { ex in
                    Button {
                        editing = ex                      // ← selecciona el item a editar
                        // ya NO activamos ningún booleano aquí
                    } label: {
                        ExerciseRow(ex: ex)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for idx in offsets {
                        let ex = items[idx]
                        context.delete(ex)
                    }
                    try? context.save()
                }
            }
        }
        .searchable(text: $search,
            placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Optional tags explícitas para evitar ambigüedad
                    Picker("Category", selection: $selected) {
                        Text("All").tag(Optional<MuscleGroup>.none)
                        Text("Core").tag(Optional(MuscleGroup.core))
                        Text("Chest/Back").tag(Optional(MuscleGroup.chestBack))
                        Text("Arms").tag(Optional(MuscleGroup.arms))
                        Text("Legs").tag(Optional(MuscleGroup.legs))
                    }
                } label: {
                    Label(selected?.display ?? "All",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true               // ← modo crear
                } label: { Label("Add", systemImage: "plus") }
            }
        }
        .navigationTitle("Manage trainings")
        .sheet(item: $editing) { ex in
            NavigationStack {
                ExerciseFormView(
                    exercise: ex,
                    onSave: { try? context.save() }
                )
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                ExerciseFormView(
                    exercise: nil,
                    onSave: { try? context.save() }
                )
            }
        }
    }
}

private struct ExerciseRow: View {
    let ex: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ex.name).font(.headline)
            Text(ex.muscleGroup.display)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension MuscleGroup {
    var display: String {
        switch self {
        case .core:       return "Core"
        case .chestBack:  return "Chest/Back"
        case .arms:       return "Arms"
        case .legs:       return "Legs"
        default:          return "All"
        }
    }
}
