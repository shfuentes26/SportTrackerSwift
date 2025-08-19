import SwiftUI
import SwiftData


// Selector de tipo de entrenamiento
enum TrainingType: String, CaseIterable, Identifiable {
    case running = "Running"
    case gym = "Gym"
    var id: String { rawValue }
}
private enum GymCategory: String, CaseIterable, Identifiable {
    case core = "Core"
    case chestBack = "Chest/Back"
    case arms = "Arms"
    case legs = "Legs"
    var id: String { rawValue }
}


struct NewView: View {
    @Environment(\.modelContext) private var context
    
    @State private var vm: NewViewModel? = nil

    // Picker de tipo
    @State private var selectedType: TrainingType = .running
    
    @State private var selectedGymCategory: GymCategory = .core
    @State private var showAddExercise: Bool = false

    // --- Running inputs ---
    @State private var runDate: Date = Date()
    @State private var runDistanceKm: String = ""
    @State private var runH: String = ""   // horas (hh)
    @State private var runM: String = ""   // minutos (mm)
    @State private var runS: String = ""   // segundos (ss)
    @State private var runNotes: String = ""

    // --- Gym inputs ---
    @Query(sort: [SortDescriptor(\Exercise.name, order: .forward)])
    private var exercises: [Exercise]
    @State private var gymDate: Date = Date()
    @State private var gymNotes: String = ""
    @State private var setInputs: [SetInput] = [SetInput()]

    // --- Alerts ---
    @State private var showSaved: Bool = false
    @State private var errorMsg: String? = nil

    init() {} // evita init(exercises:) sintetizado por @Query

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Type", selection: $selectedType) {
                    ForEach(TrainingType.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedType == .running {
                    runningForm
                } else {
                    gymForm
                }

                Spacer(minLength: 12)

                Button(action: saveTapped) {
                    Text("Save \(selectedType.rawValue)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("New")
            .alert("Training saved successfully", isPresented: $showSaved) {
                Button("OK", role: .cancel) { }
            }
            .alert("Validation", isPresented: .constant(errorMsg != nil), actions: {
                Button("OK", role: .cancel) { errorMsg = nil }
            }, message: { Text(errorMsg ?? "") })
        }.task {
            if vm == nil {
                vm = NewViewModel(
                    context: context,
                    runningRepo: SwiftDataRunningRepository(context: context),
                    strengthRepo: SwiftDataStrengthRepository(context: context)
                )
            }
        }
    }

    // MARK: - Running form

    private var runningForm: some View {
        Form {
            DatePicker("Date", selection: $runDate, displayedComponents: [.date, .hourAndMinute])
            HStack {
                TextField("Distance (km)", text: $runDistanceKm)
                    .keyboardType(.decimalPad)
                Text("km").foregroundStyle(.secondary)
            }
            Section("Duration (hh:mm:ss)") {
                HStack(spacing: 6) {
                    TimeBox(placeholder: "hh", text: $runH)
                    Text(":").monospacedDigit()
                    TimeBox(placeholder: "mm", text: $runM)
                    Text(":").monospacedDigit()
                    TimeBox(placeholder: "ss", text: $runS)
                }
                Text("Ejemplo: 1:02:30 → 1 hora, 2 minutos, 30 segundos")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Notes") {
                TextField("Optional", text: $runNotes, axis: .vertical)
            }
        }
    }

    // MARK: - Gym form

    private var gymForm: some View {
        Form {
            DatePicker("Date", selection: $gymDate, displayedComponents: [.date, .hourAndMinute])
            Section("Category") {
                Picker("Category", selection: $selectedGymCategory) {
                    ForEach(GymCategory.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    showAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                }
            }
            Section("Sets") {
                ForEach($setInputs) { $input in
                    SetRow(input: $input, allExercises: filteredExercises)
                }
                .onDelete { idx in
                    setInputs.remove(atOffsets: idx)
                }

                Button {
                    setInputs.append(SetInput())
                } label: {
                    Label("Add Set", systemImage: "plus.circle.fill")
                }
            }

            Section("Notes") {
                TextField("Optional", text: $gymNotes, axis: .vertical)
            }
        }.sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(selectedCategory: $selectedGymCategory)
        }
    }

    // MARK: - Save

    private func saveTapped() {
        guard let vm else { return }

        switch selectedType {
        case .running:
            guard
                let km = vm.validateDistance(runDistanceKm),       // "12,3" o "12.3"
                let seconds = vm.validateDuration(h: runH, m: runM, s: runS) // hh:mm:ss
            else {
                errorMsg = "Please enter a positive distance and a duration in hh:mm:ss."
                return
            }

            do {
                try vm.saveRunning(date: runDate,
                                   km: km,
                                   seconds: seconds,
                                   notes: runNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : runNotes)
                // reset UI
                runDistanceKm = ""
                runH = ""; runM = ""; runS = ""
                runNotes = ""
                showSaved = true
            } catch {
                errorMsg = "Could not save: \(error.localizedDescription)"
            }

        case .gym:
            // Mapea tus SetInput de la vista a un DTO del VM
            let mapped: [NewViewModel.NewTrainingSet] = setInputs.enumerated().compactMap { (idx, input) in
                let reps = Int(input.reps) ?? 0
                guard reps > 0 else { return nil }
                let weight = Double(input.weight.replacingOccurrences(of: ",", with: ".")) // opcional
                let exercise = input.exercise ?? filteredExercises.first ?? exercises.first
                guard let ex = exercise else { return nil }
                return .init(exercise: ex, order: idx + 1, reps: reps, weightKg: weight)
            }

            guard !mapped.isEmpty else {
                errorMsg = "Add at least one set with reps."
                return
            }

            do {
                try vm.saveGym(date: gymDate,
                               notes: gymNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gymNotes,
                               sets: mapped)
                // reset UI
                setInputs = [SetInput()]
                gymNotes = ""
                showSaved = true
            } catch {
                errorMsg = "Could not save: \(error.localizedDescription)"
            }
        }
    }
    
    private func mapGroup(_ g: MuscleGroup) -> GymCategory? {
        switch g {
        case .core:            return .core
        case .chestBack:    return .chestBack
        case .arms:            return .arms
        case .legs:            return .legs
        default:               return nil   // ajusta si tu enum tiene más casos
        }
    }

    private var filteredExercises: [Exercise] {
        exercises.filter { ex in
            mapGroup(ex.muscleGroup) == selectedGymCategory
        }
    }

   

   

    


   
}

// MARK: - TimeBox (cajitas hh:mm:ss)

private struct TimeBox: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { text },
            set: { newValue in
                let digits = newValue.filter { $0.isNumber }
                if placeholder == "hh" {
                    text = String(digits.prefix(3))
                } else {
                    text = String(digits.prefix(2))
                }
            }
        ))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .frame(width: placeholder == "hh" ? 52 : 42)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .monospacedDigit()
    }
}

// MARK: - SetInput + SetRow (UI de sets Gym)

struct SetInput: Identifiable, Hashable {
    let id = UUID()
    var exercise: Exercise? = nil
    var reps: String = ""
    var weight: String = "" // kg (opcional)
}

struct SetRow: View {
    @Binding var input: SetInput
    var allExercises: [Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allExercises.isEmpty {
                HStack {
                    Text("No exercises in this category").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                Picker("Exercise", selection: Binding(
                    get: { input.exercise ?? allExercises.first },
                    set: { input.exercise = $0 }
                )) {
                    ForEach(allExercises, id: \.id) { ex in
                        Text(ex.name).tag(Optional(ex))
                    }
                }
            }

            HStack {
                TextField("Reps", text: $input.reps)
                    .keyboardType(.numberPad)
                Divider()
                TextField("Weight (kg)", text: $input.weight)
                    .keyboardType(.decimalPad)
            }
        }
    }
    
}

private struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Binding var selectedCategory: GymCategory

    @State private var name: String = ""
    @State private var weighted: Bool = false
    @State private var chestBackChoice: ChestBack = .chest

    private enum ChestBack: String, CaseIterable, Identifiable {
        case chest = "Chest"
        case back  = "Back"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Info") {
                    TextField("Name", text: $name)
                    Toggle("Weighted (kg)", isOn: $weighted)
                }

                if selectedCategory == .chestBack {
                    Section("Group") {
                        Picker("Group", selection: $chestBackChoice) {
                            ForEach(ChestBack.allCases) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Text("Will be added to \(selectedCategory.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let group: MuscleGroup = {
            switch selectedCategory {
            case .core:       return .core
            case .arms:       return .arms
            case .legs:       return .legs
            case .chestBack:  return .chestBack
            }
        }()

        let ex = Exercise(name: name.trimmingCharacters(in: .whitespaces),
                          muscleGroup: group,
                          isWeighted: weighted,
                          isCustom: true)
        context.insert(ex)
        do { try context.save() } catch { print("Save exercise error: \(error)") }
        dismiss()
    }
}


// MARK: - Preview

#Preview {
    NewView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
