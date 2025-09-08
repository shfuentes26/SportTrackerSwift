import SwiftUI
import SwiftData

struct ExercisesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Exercise.name, order: .forward)])
    private var allExercises: [Exercise]

    @StateObject private var viewModel = ExercisesListViewModel()
    @State private var creating = false
    @State private var editing: Exercise? = nil

    var body: some View {
        List {
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
                        creating = false
                    } label: { ExerciseRow(ex: ex) }
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
                    creating = true
                } label: { Label("Add", systemImage: "plus") }
            }
        }
        .navigationTitle("Manage trainings")
        .sheet(item: $editing) { ex in
            NavigationStack {
                ExerciseFormView(exercise: ex, onSave: { try? context.save() })
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                ExerciseFormView(exercise: nil, onSave: { try? context.save() })
            }
        }
        .onAppear {
            // 🔎 LOG: identidad (puntero) del container que ve ESTA vista
            let ptr = Unmanaged.passUnretained(context.container).toOpaque()
            print("[VIEW] modelContext.container ptr =", ptr)

            // 🔎 LOG: duplicados por nombre (diagnóstico)
            ExercisesListViewModel.logDuplicates(context: context, tag: "ExercisesListView.onAppear")
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
        case .core: return "Core"
        case .chestBack: return "Chest/Back"
        case .arms: return "Arms"
        case .legs: return "Legs"
        default: return "All"
        }
    }
}
