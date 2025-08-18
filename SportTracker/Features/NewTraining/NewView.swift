import SwiftUI
import SwiftData

// Selector de tipo de entrenamiento
enum TrainingType: String, CaseIterable, Identifiable {
    case running = "Running"
    case gym = "Gym"
    var id: String { rawValue }
}

struct NewView: View {
    @Environment(\.modelContext) private var context

    // Picker de tipo
    @State private var selectedType: TrainingType = .running

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

            Section("Sets") {
                ForEach($setInputs) { $input in
                    SetRow(input: $input, allExercises: exercises)
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
        }
    }

    // MARK: - Save

    private func saveTapped() {
        switch selectedType {
        case .running:
            saveRunning()
        case .gym:
            saveGym()
        }
    }

    private func settingsOrCreate() -> Settings {
        if let s = try? context.fetch(FetchDescriptor<Settings>()).first {
            return s
        } else {
            let s = Settings()
            context.insert(s)
            return s
        }
    }

    private func parseDouble(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func totalSeconds(h: String, m: String, s: String) -> Int? {
        let hh = Int(h) ?? 0
        let mm = Int(m) ?? 0
        let ss = Int(s) ?? 0
        let total = hh*3600 + mm*60 + ss
        return total > 0 ? total : nil
    }

    private func saveRunning() {
        guard let distanceKm = parseDouble(runDistanceKm), distanceKm > 0,
              let seconds = totalSeconds(h: runH, m: runM, s: runS) else {
            errorMsg = "Please enter a positive distance and a duration in hh:mm:ss."
            return
        }

        let session = RunningSession(
            date: runDate,
            durationSeconds: seconds,
            distanceMeters: distanceKm * 1000.0,
            notes: runNotes.isEmpty ? nil : runNotes
        )

        let s = settingsOrCreate()
        session.totalPoints = PointsCalculator.score(running: session, settings: s)

        context.insert(session)
        do {
            try context.save()
            // reset
            runDistanceKm = ""
            runH = ""; runM = ""; runS = ""
            runNotes = ""
            showSaved = true
        } catch {
            errorMsg = "Could not save: \(error.localizedDescription)"
        }
    }

    private func saveGym() {
        // Si no hay ejercicios, crea uno por defecto
        let defaultExercise: Exercise = {
            if let first = exercises.first { return first }
            let ex = Exercise(name: "Custom", muscleGroup: .core, isWeighted: false, isCustom: true)
            context.insert(ex)
            return ex
        }()

        // Valida y crea sets
        let validSets: [StrengthSet] = setInputs.enumerated().compactMap { (idx, input) in
            let ex = input.exercise ?? defaultExercise
            let reps = Int(input.reps) ?? 0
            guard reps > 0 else { return nil }
            let weight = Double(input.weight.replacingOccurrences(of: ",", with: "."))
            return StrengthSet(exercise: ex, order: idx + 1, reps: reps, weightKg: weight)
        }

        guard !validSets.isEmpty else {
            errorMsg = "Add at least one set with reps."
            return
        }

        let session = StrengthSession(date: gymDate, notes: gymNotes.isEmpty ? nil : gymNotes)
        for s in validSets {
            s.session = session
            session.sets.append(s)
        }

        let st = settingsOrCreate()
        session.totalPoints = PointsCalculator.score(strength: session, settings: st)

        context.insert(session)
        do {
            try context.save()
            // reset
            setInputs = [SetInput()]
            gymNotes = ""
            showSaved = true
        } catch {
            errorMsg = "Could not save: \(error.localizedDescription)"
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
            Picker("Exercise", selection: Binding(
                get: { input.exercise ?? allExercises.first },
                set: { input.exercise = $0 }
            )) {
                ForEach(allExercises, id: \.id) { ex in
                    Text(ex.name).tag(Optional(ex))
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

// MARK: - Preview

#Preview {
    NewView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
