import SwiftUI
import SwiftData

struct GymView: View {
    @Environment(\.modelContext) private var context
    @State private var editingSession: StrengthSession? = nil

    @State private var weekStart: Date = Calendar.iso8601Monday.startOfWeek(for: Date())

    private var currentWeekLabel: String {
        let cal = Calendar.iso8601Monday
        let end = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = Locale.current
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: end))"
    }

    @State private var vm: GymViewModel? = nil

    @Query(sort: [SortDescriptor(\StrengthSession.date, order: .reverse)])
    private var sessions: [StrengthSession]
    @Query private var settingsList: [Settings]
    private var usePounds: Bool { settingsList.first?.prefersPounds ?? false }

    private enum GymFilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case core = "Core"
        case chestBack = "Chest/Back"
        case arms = "Arms"
        case legs = "Legs"
        var id: String { rawValue }
    }

    private func gymDetails(_ s: StrengthSession) -> String {
        if s.sets.isEmpty { return "No sets" }
        let items = s.sets
            .sorted(by: { $0.order < $1.order })
            .prefix(3)
            .map { set in
                let reps = "\(set.reps)"
                let w = (set.weightKg ?? 0) > 0
                    ? " @ " + UnitFormatters.weight(set.weightKg!, usePounds: usePounds)
                    : ""
                return "\(set.exercise.name) \(reps)\(w)"
            }
        var line = items.joined(separator: " • ")
        if s.sets.count > 3 { line += " …" }
        return line
    }

    private var filteredSessions: [StrengthSession] {
        sessions.filter { s in
            selectedCategory == .all || session(s, matches: selectedCategory)
        }
    }

    private func session(_ s: StrengthSession, matches cat: GymFilterCategory) -> Bool {
        let cats = Set(s.sets.compactMap { mapGroup($0.exercise.muscleGroup) })
        return cats.contains(cat)
    }

    private func mapGroup(_ g: MuscleGroup) -> GymFilterCategory? {
        switch g {
        case .core:       return .core
        case .chestBack:  return .chestBack
        case .arms:       return .arms
        case .legs:       return .legs
        default:          return nil
        }
    }

    @State private var selectedCategory: GymFilterCategory = .all

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(GymFilterCategory.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                GymHistoryChart(sessions: filteredSessions)
                    .id(selectedCategory)

                List {
                    if filteredSessions.isEmpty {
                        ContentUnavailableView(
                            selectedCategory == .all
                            ? "There are no gym trainings yet"
                            : "No sessions for \(selectedCategory.rawValue)",
                            systemImage: "dumbbell"
                        )
                    } else {
                        Section("Past Trainings") {
                            ForEach(filteredSessions) { s in
                                NavigationLink {
                                    TrainingDetailView(item: .gym(s))
                                } label: {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(SummaryView.formatDate(s.date)).font(.headline)
                                            Spacer()
                                            Text("\(Int(s.totalPoints)) pts").foregroundStyle(.secondary)
                                        }
                                        Text(gymDetails(s))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { vm?.delete(s) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { editingSession = s } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .brandHeaderSpacer()
            .navigationTitle("Gym")
        }
        .task {
            if vm == nil {
                vm = GymViewModel(
                    repo: SwiftDataStrengthRepository(context: context),
                    context: context
                )
                vm?.load()
            }
        }
        .sheet(item: $editingSession) { sess in
            EditGymSheet(session: sess)
        }
    }

    @MainActor
    private func delete(session: StrengthSession) {
        context.delete(session)
        do { try context.save() } catch {
            print("Delete error: \(error)")
        }
    }
}

extension StrengthSession: Identifiable {}

// MARK: - Editor con sets (respeta lb/kg)

struct EditGymSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Exercise.name, order: .forward)])
    private var exercises: [Exercise]

    @Query private var settingsList: [Settings]
    private var usePounds: Bool { settingsList.first?.prefersPounds ?? false }

    @Bindable var session: StrengthSession

    init(session: StrengthSession) { self.session = session }

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

                    ForEach(session.sets) { set in
                        SetEditorRow(set: set, exercises: exercises, usePounds: usePounds)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
                ToolbarItem(placement: .keyboard) { Button("Done") { hideKeyboard() } }
            }
        }
    }

    // MARK: - Set helpers

    private func addSet() {
        let ex: Exercise
        if let first = exercises.first {
            ex = first
        } else {
            ex = Exercise(name: "Custom", muscleGroup: .core, isWeighted: false, isCustom: true)
            context.insert(ex)
        }
        let newOrder = (session.sets.map(\.order).max() ?? 0) + 1
        let newSet = StrengthSet(exercise: ex, order: newOrder, reps: 10, weightKg: nil)
        newSet.session = session
        session.sets.append(newSet)
    }

    private func deleteSets(at offsets: IndexSet) {
        for index in offsets {
            let set = session.sets[index]
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
        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        return Int(max(0, PointsCalculator.score(strength: session, settings: settings)))
    }

    private func save() {
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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - Fila de edición de un set (lb/kg)

private struct SetEditorRow: View {
    @Bindable var set: StrengthSet
    let exercises: [Exercise]
    let usePounds: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                TextField("Reps", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)

                Divider()

                TextField(usePounds ? "Weight (lb)" : "Weight (kg)", text: Binding(
                    get: {
                        guard let wKg = set.weightKg else { return "" }
                        let value = usePounds ? (wKg * 2.2046226218) : wKg
                        return String(format: usePounds ? "%.0f" : "%.1f", value)
                    },
                    set: { txt in
                        let t = txt.replacingOccurrences(of: ",", with: ".")
                        if let entered = Double(t) {
                            set.weightKg = usePounds ? (entered / 2.2046226218) : entered
                        } else {
                            set.weightKg = nil
                        }
                    }
                ))
                .keyboardType(.decimalPad)
            }
        }
    }
}

fileprivate extension Calendar {
    static var iso8601Monday: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }
}

#Preview {
    GymView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
