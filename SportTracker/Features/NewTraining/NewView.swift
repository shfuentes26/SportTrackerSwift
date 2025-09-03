import SwiftUI
import SwiftData
import MapKit

// Selector de tipo de entrenamiento
enum TrainingType: String, CaseIterable, Identifiable {
    case running = "Running"
    case gym = "Gym"
    var id: String { rawValue }
}

struct NewView: View {
    @Environment(\.modelContext) private var context
    @State private var vm: NewViewModel? = nil

    // Picker de tipo
    @State private var selectedType: TrainingType = .running

    // Categoría del selector de Gym (tipo compartido)
    @State private var selectedGymCategory: ExerciseCategory = .core
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

    @Query private var settingsList: [Settings]
    private var useMiles: Bool  { settingsList.first?.prefersMiles  ?? false }
    private var usePounds: Bool { settingsList.first?.prefersPounds ?? false }
    
    private enum RunningMode { case choose, manual }

    @State private var goLiveRun = false
    @State private var runningMode: RunningMode = .choose
    
    // -- Map --
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var tracking: MapUserTrackingMode = .follow
    @State private var locManager = CLLocationManager()
    
    // al principio de la struct NewView
    @FocusState private var focusedField: Field?
    private enum Field { case runDistance, runH, runM, runS, runNotes }

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

                if selectedType == .gym || (selectedType == .running && runningMode == .manual) {
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
            }
            .navigationTitle("New Training")
            .brandHeaderSpacer()
            .alert("Training saved successfully", isPresented: $showSaved) {
                Button("OK") {
                    NotificationCenter.default.post(name: .navigateToSummary, object: nil)
                }
            }
            .alert("Validation", isPresented: .constant(errorMsg != nil), actions: {
                Button("OK", role: .cancel) { errorMsg = nil }
            }, message: { Text(errorMsg ?? "") })
        }
        .brandNavBar()
        .task {
            if vm == nil {
                vm = NewViewModel(
                    context: context,
                    runningRepo: SwiftDataRunningRepository(context: context),
                    strengthRepo: SwiftDataStrengthRepository(context: context)
                )
            }
        }
    }
    
    // Cerrar teclado (UIKit)
    private func dismissKeyboard() {
    #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    #endif
    }
    
    private func endEditing() {
        focusedField = nil
        dismissKeyboard()
    }

    // MARK: - Running form
    
    // MARK: - Running form
    @State private var hh = ""
    @State private var mm = ""
    @State private var ss = ""

    private var runningForm: some View {
        Group {
            if runningMode == .choose {
                VStack(spacing: 16) {
                    // Mapa centrado en la posición del usuario
                    Map(coordinateRegion: $region,
                        showsUserLocation: true,
                        userTrackingMode: $tracking)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onAppear {
                        // Pedimos permiso de localización para mostrar el punto azul
                        if locManager.authorizationStatus == .notDetermined {
                            locManager.requestWhenInUseAuthorization()
                        }
                        tracking = .follow
                    }

                    // Botones debajo del mapa
                    VStack(spacing: 10) {
                        Button {
                            goLiveRun = true
                        } label: {
                            Text("Start Workout")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.blue)
                                )
                        }

                        Button {
                            runningMode = .manual
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    focusedField = .runDistance
                                }
                        } label: {
                            Text("Track manually")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.gray.opacity(0.12))
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.horizontal)
                // NavigationLink oculto para LiveRun
                .background(
                    NavigationLink("", isActive: $goLiveRun) {
                        LiveRunView()
                    }
                    .hidden()
                )

            } else {
                // Paso 2: formulario MANUAL
                Form {
                    Section {
                        Button {
                            withAnimation(.easeInOut) { runningMode = .choose }
                            endEditing()
                        } label: {
                            Label("Back to options", systemImage: "chevron.left")
                        }
                        .buttonStyle(.plain)
                    }

                    DatePicker("Date", selection: $runDate, displayedComponents: [.date, .hourAndMinute])

                    HStack {
                        TextField("Distance (\(useMiles ? "mi" : "km"))", text: $runDistanceKm)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .runDistance)
                        Text(useMiles ? "mi" : "km").foregroundStyle(.secondary)
                    }

                    Section("Duration (hh:mm:ss)") {
                        DurationFields(hours: $hh, minutes: $mm, seconds: $ss)
                        Text("Example: 1:02:30 → 1 hour, 2 minutes, 30 seconds")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Section("Notes") {
                        TextField("Optional", text: $runNotes, axis: .vertical)
                            .focused($focusedField, equals: .runNotes)   // ← añade foco también aquí
                    }
                }
                .scrollDismissesKeyboard(.interactively)                     // arrastrar para cerrar
                .contentShape(Rectangle())                                    // toda la zona es “tapeable”
                .simultaneousGesture(TapGesture().onEnded { endEditing() })   // tap para cerrar
                .toolbar {                                                     // botón “Done” en el teclado
                    ToolbarItem(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button("Done") { endEditing() }
                        }
                    }
                }
                .id(runningMode)
                .animation(.easeInOut, value: runningMode)
            }
        }
    }

    // MARK: - Gym form

    private var gymForm: some View {
        Form {
            DatePicker("Date", selection: $gymDate, displayedComponents: [.date, .hourAndMinute])

            Section("Category") {
                Picker("Category", selection: $selectedGymCategory) {
                    Text("Core").tag(ExerciseCategory.core)
                    Text("Chest/Back").tag(ExerciseCategory.chestBack)
                    Text("Arms").tag(ExerciseCategory.arms)
                    Text("Legs").tag(ExerciseCategory.legs)
                }
                .pickerStyle(.segmented)

                Button {
                    showAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                }
            }

            Section("Exercise") {
                // Un solo ejercicio/set por entrenamiento
                SetRow(
                    input: $setInputs[0],              // <- siempre 1
                    allExercises: filteredExercises,
                    usePounds: usePounds
                )
            }

            Section("Notes") {
                TextField("Optional", text: $gymNotes, axis: .vertical)
            }
        }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(selectedCategory: $selectedGymCategory)
        }
        // 👇 mismos cierres de teclado que ya pusimos en running manual
        .scrollDismissesKeyboard(.interactively)                     // arrastrar para cerrar
        //.contentShape(Rectangle())                                    // toda el área recibe taps
        //.simultaneousGesture(TapGesture().onEnded { endEditing() })   // tap para cerrar
        .toolbar {                                                     // botón Done en el teclado
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") { endEditing() }
                }
            }
        }
    }

    // MARK: - Save

    private func saveTapped() {
        guard let vm else { return }

        switch selectedType {
        case .running:
            // ✅ valida distancia y duración (usa hh/mm/ss de los nuevos campos)
            guard
                let raw = vm.validateDistance(runDistanceKm),
                let seconds = vm.validateDuration(h: hh, m: mm, s: ss)
            else {
                errorMsg = "Please enter a positive distance and a duration in hh:mm:ss."
                return
            }

            // ✅ si el usuario ha escrito millas, conviértelas a km para la BD
            let km = useMiles ? (raw * 1.60934) : raw

            do {
                try vm.saveRunning(
                    date: runDate,
                    km: km,
                    seconds: seconds, // ← ya es Int (desenvuelto en el guard)
                    notes: runNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : runNotes
                )

                // reset UI (resetea los campos NUEVOS)
                runDistanceKm = ""
                hh = ""; mm = ""; ss = ""
                runNotes = ""
                
                showSaved = true
            } catch {
                errorMsg = error.localizedDescription
            }

        case .gym:
            // Mapea tus SetInput a DTO del VM
            guard let input = setInputs.first else {
                errorMsg = "Add at least one set with reps."
                return
            }

            let reps = Int(input.reps) ?? 0
            guard reps > 0 else {
                errorMsg = "Add at least one set with reps."
                return
            }

            let entered = Double(input.weight.replacingOccurrences(of: ",", with: "."))
            let weightKg = entered.map { usePounds ? ($0 / 2.20462) : $0 }

            let exercise = filteredExercises.first(where: { $0.id == input.exerciseId })
                ?? filteredExercises.first
                ?? exercises.first

            guard let ex = exercise else {
                errorMsg = "Select an exercise."
                return
            }

            let mapped: [NewViewModel.NewTrainingSet] = [
                .init(exercise: ex, order: 1, reps: reps, weightKg: weightKg)
            ]


            do {
                try vm.saveGym(
                    date: gymDate,
                    notes: gymNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gymNotes,
                    sets: mapped
                )
                // reset UI
                setInputs = [SetInput()]
                gymNotes = ""
                showSaved = true
            } catch {
                errorMsg = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    private func mapGroup(_ g: MuscleGroup) -> ExerciseCategory? {
        switch g {
        case .core:       return .core
        case .chestBack:  return .chestBack
        case .arms:       return .arms
        case .legs:       return .legs
        default:          return nil   // ajusta si tu enum tiene más casos
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
    var exerciseId: UUID? = nil     // <-- usar UUID?, no Exercise?
    var reps: String = ""
    var weight: String = ""         // kg (opcional)
}

struct SetRow: View {
    @Binding var input: SetInput
    var allExercises: [Exercise]
    var usePounds: Bool = false

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { input.exerciseId ?? allExercises.first?.id },
            set: { input.exerciseId = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allExercises.isEmpty {
                HStack {
                    Text("No exercises in this category").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                Picker("Exercise", selection: selectionBinding) {
                    ForEach(allExercises, id: \.id) { ex in
                        Text(ex.name).tag(ex.id as UUID?)   // tag del MISMO tipo que selection (UUID?)
                    }
                }
                .pickerStyle(.menu)                         // menú desplegable en iPhone
                .onAppear {
                    // Si no hay nada guardado aún, fija una selección real
                    if input.exerciseId == nil {
                        input.exerciseId = allExercises.first?.id
                    }
                }
                .onChange(of: allExercises.map(\.id)) { ids in
                    // Si cambia la categoría y la selección ya no existe, usa la primera opción
                    if let cur = input.exerciseId, !ids.contains(cur) {
                        input.exerciseId = ids.first
                    }
                }
            }

            HStack {
                TextField("Reps", text: $input.reps)
                    .keyboardType(.numberPad)
                Divider()
                TextField("Weight (\(usePounds ? "lb" : "kg"))", text: $input.weight)
                    .keyboardType(.decimalPad)
            }
        }
    }
    
}

// MARK: - AddExerciseSheet (anidada) ----------------------------------------

extension NewView {
    struct AddExerciseSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var context

        @Binding var selectedCategory: ExerciseCategory

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
            // Mapear ExerciseCategory -> MuscleGroup del modelo
            let group: MuscleGroup = {
                switch selectedCategory {
                case .core:      return .core
                case .arms:      return .arms
                case .legs:      return .legs
                case .chestBack: return .chestBack
                case .all:       return .chestBack // no debería llegar, pero asignamos algo sensato
                }
            }()

            let ex = Exercise(
                name: name.trimmingCharacters(in: .whitespaces),
                muscleGroup: group,
                isWeighted: weighted,
                isCustom: true
            )
            context.insert(ex)
            do { try context.save() } catch { print("Save exercise error: \(error)") }
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    NewView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
