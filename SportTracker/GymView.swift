import SwiftUI
import SwiftData

struct GymView: View {
    @Environment(\.modelContext) private var context
    @State private var editingSession: StrengthSession? = nil

    @Query(sort: [SortDescriptor(\StrengthSession.date, order: .reverse)])
    private var sessions: [StrengthSession]

    init() {} // evita el init(sessions:) sintetizado por @Query

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "There are no gym trainings yet",
                        systemImage: "dumbbell"
                    )
                } else {
                    ForEach(sessions) { s in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(SummaryView.formatDate(s.date)).font(.headline)
                                Spacer()
                                Text("\(Int(s.totalPoints)) pts").foregroundStyle(.secondary)
                            }
                            Text("\(s.sets.count) set(s)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(session: s) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { editingSession = s } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
                }
            }

            .navigationTitle("Gym")
        }
        .sheet(item: $editingSession) { sess in
            EditGymSheet(session: sess)
        }
    }

    // MARK: - Actions

    @MainActor
    private func delete(session: StrengthSession) {
        // Borra la sesión (sus sets se eliminan por deleteRule .cascade)
        context.delete(session)
        do { try context.save() } catch {
            print("Delete error: \(error)")
        }
    }
}

// Necesario para usar .sheet(item:) con StrengthSession
extension StrengthSession: Identifiable {}


// MARK: - Editor con sets

private struct EditGymSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // Lista de ejercicios disponibles para el picker
    @Query(sort: [SortDescriptor(\Exercise.name, order: .forward)])
    private var exercises: [Exercise]

    // @Bindable permite editar directamente el modelo @Model
    @Bindable var session: StrengthSession

    init(session: StrengthSession) {
        self.session = session
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $session.date, displayedComponents: [.date, .hourAndMinute])

                Section("Sets") {
                    if exercises.isEmpty {
                        Text("No exercises found. Add some in your library.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    // Editor de cada set
                    ForEach(session.sets) { set in
                        SetEditorRow(set: set, exercises: exercises)
                    }
                    .onDelete(perform: deleteSets)
                    .onMove(perform: moveSets)

                    Button {
                        addSet()
                    } label: {
                        Label("Add Set", systemImage: "plus.circle.fill")
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: Binding(
                        get: { session.notes ?? "" },
                        set: { session.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                }

                Section {
                    Text("Points preview: \(pointsPreview()) pts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Gym")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { hideKeyboard() }
                }
            }
        }
    }

    // MARK: - Set helpers

    private func addSet() {
        // Elige un ejercicio por defecto (si no hay, crea uno básico)
        let ex: Exercise
        if let first = exercises.first {
            ex = first
        } else {
            ex = Exercise(name: "Custom", muscleGroup: .core, isWeighted: false, isCustom: true)
            context.insert(ex)
        }
        let newOrder = (session.sets.map(\.order).max() ?? 0) + 1
        let newSet = StrengthSet(exercise: ex, order: newOrder, reps: 10, weightKg: nil)
        // Vincula a la sesión
        newSet.session = session
        session.sets.append(newSet)
        // No es necesario insert explícito; se persiste al guardar
    }

    private func deleteSets(at offsets: IndexSet) {
        for index in offsets {
            let set = session.sets[index]
            // Eliminar del contexto si ya estaba guardado
            context.delete(set)
        }
        session.sets.remove(atOffsets: offsets)
        renumberOrders()
    }

    private func moveSets(from source: IndexSet, to destination: Int) {
        session.sets.move(fromOffsets: source, toOffset: destination)
        renumberOrders()
    }

    private func renumberOrders() {
        for (i, set) in session.sets.enumerated() {
            set.order = i + 1
        }
    }

    private func pointsPreview() -> Int {
        // Calcula puntos con los valores actuales (sin guardar)
        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        return Int(max(0, PointsCalculator.score(strength: session, settings: settings)))
    }

    private func save() {
        // Recalcula puntos y guarda
        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        if settings.persistentModelID == nil { context.insert(settings) }
        session.totalPoints = PointsCalculator.score(strength: session, settings: settings)

        do { try context.save() } catch {
            print("Save edit error: \(error)")
        }
        dismiss()
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - Fila de edición de un set

private struct SetEditorRow: View {
    // @Bindable sobre el set para editar sus propiedades
    @Bindable var set: StrengthSet
    let exercises: [Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Picker de ejercicio por id (UUID), para evitar problemas de Equatable
            Picker("Exercise", selection: Binding(
                get: { set.exercise.id },
                set: { newId in
                    if let found = exercises.first(where: { $0.id == newId }) {
                        set.exercise = found
                    }
                }
            )) {
                ForEach(exercises, id: \.id) { ex in
                    Text(ex.name).tag(ex.id)
                }
            }

            HStack {
                // Reps como Int con binding nativo
                TextField("Reps", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)

                Divider()

                // Weight opcional (kg) con binding manual a String
                TextField("Weight (kg)", text: Binding(
                    get: { set.weightKg.map { String($0) } ?? "" },
                    set: { txt in
                        let t = txt.replacingOccurrences(of: ",", with: ".")
                        set.weightKg = Double(t)
                    }
                ))
                .keyboardType(.decimalPad)
            }
        }
    }
}

#Preview {
    GymView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
