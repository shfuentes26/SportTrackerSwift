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

    /// View model storing the current search string and selected category.
    /// Using a ``@StateObject`` here ensures that the model is created
    /// once per view lifecycle and is retained across view reloads.
    @StateObject private var viewModel = ExercisesListViewModel()
    @State private var showingForm = false
    @State private var editing: Exercise? = nil

    // Filtering is delegated to the view model. See ``ExercisesListViewModel``.

    var body: some View {
        List {
            // Obtain the filtered list from the view model. The model
            // reads the current search text and selected muscle group.
            let items = viewModel.filteredExercises(from: allExercises)
            if items.isEmpty {
                ContentUnavailableView(
                    "No exercises yet",
                    systemImage: "dumbbell",
                    description: Text("Add your first exercise with the + button.")
                )
            } else {
                ForEach(items) { ex in
                    Button {
                        editing = ex
                        showingForm = true
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
        .searchable(text: $viewModel.search,
            placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Optional tags explícitas para evitar ambigüedad
                    Picker("Category", selection: $viewModel.selected) {
                        Text("All").tag(Optional<MuscleGroup>.none)
                        Text("Core").tag(Optional(MuscleGroup.core))
                        Text("Chest/Back").tag(Optional(MuscleGroup.chestBack))
                        Text("Arms").tag(Optional(MuscleGroup.arms))
                        Text("Legs").tag(Optional(MuscleGroup.legs))
                    }
                } label: {
                    Label(viewModel.selected?.display ?? "All",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = nil
                    showingForm = true
                } label: { Label("Add", systemImage: "plus") }
            }
        }
        .navigationTitle("Manage trainings")
        .sheet(isPresented: $showingForm) {
            NavigationStack {
                ExerciseFormView(
                    exercise: editing,
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
