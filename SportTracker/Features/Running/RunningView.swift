import SwiftUI
import SwiftData

enum RunningTab: String, CaseIterable, Identifiable {
    case progress = "Progress"
    case records  = "Records"
    var id: String { rawValue }
}

struct RunningView: View {
    @Environment(\.modelContext) private var context
    @State private var editingRun: RunningSession? = nil
    
    @State private var vm: RunningViewModel? = nil
  

    @Query(sort: [SortDescriptor(\RunningSession.date, order: .reverse)])
    private var runs: [RunningSession]
    
    @Query private var settingsList: [Settings]
    private var useMiles: Bool { settingsList.first?.prefersMiles ?? false }

    @State private var selectedTab: RunningTab = .progress

    init() {} // evita init(runs:) sintetizado por @Query

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // Segmented control bajo la cabecera verde
                Picker("", selection: $selectedTab) {
                    Text("Progress").tag(RunningTab.progress)
                    Text("Records").tag(RunningTab.records)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Contenido de cada tab
                if selectedTab == .progress {
                    // ✅ Tu vista actual intacta
                    RunningHistoryChart()

                    List {
                        if runs.isEmpty {
                            ContentUnavailableView(
                                "There are no running trainings yet",
                                systemImage: "figure.run"
                            )
                        } else {
                            Section("Past Trainings") {
                                ForEach(runs) { r in
                                    NavigationLink {
                                        TrainingDetailView(item: .running(r))
                                    } label: {
                                        VStack(alignment: .leading) {
                                            HStack {
                                                Text(SummaryView.formatDate(r.date)).font(.headline)
                                                Spacer()
                                                Text("\(Int(r.totalPoints)) pts").foregroundStyle(.secondary)
                                            }
                                            Text("\(UnitFormatters.distance(r.distanceKm, useMiles: useMiles)) • \(UnitFormatters.pace(secondsPerKm: r.paceSecondsPerKm, useMiles: useMiles)) • \(r.durationSeconds/60) min")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { vm?.delete(r) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button { editingRun = r } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // ✅ Nueva vista de records
                    RunningRecordsView(runs: runs, useMiles: useMiles)
                }
            }
            .navigationTitle("Running")
            .navigationBarTitleDisplayMode(.large)          // ← nuevo
            //.toolbarBackground(.visible, for: .navigationBar) // ← nuevo
            .brandHeaderSpacer()         // mantiene el espacio bajo tu cabecera verde
        }
        .brandNavBar()
        .task {
            if vm == nil {
                vm = RunningViewModel(
                    repo: SwiftDataRunningRepository(context: context),
                    context: context
                )
                vm?.load()
            }
        }
        .sheet(item: $editingRun) { run in
            EditRunningSheet(run: run)
        }
    }

    // MARK: - Actions

    @MainActor
    private func delete(run: RunningSession) {
        context.delete(run)
        do { try context.save() } catch {
            print("Delete error: \(error)")
        }
    }
}

// Necesario para usar .sheet(item:) con RunningSession
extension RunningSession: Identifiable {}

private struct EditRunningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var run: RunningSession

    @State private var date: Date
    @State private var distanceKm: String
    @State private var hh: String
    @State private var mm: String
    @State private var ss: String
    @State private var notes: String

    init(run: RunningSession) {
        self.run = run
        _date = State(initialValue: run.date)

        // Mostrar distancia con 0-2 decimales
        _distanceKm = State(initialValue: {
            let nf = NumberFormatter()
            nf.maximumFractionDigits = 2
            nf.minimumFractionDigits = 0
            return nf.string(from: NSNumber(value: run.distanceKm)) ?? String(format: "%.2f", run.distanceKm)
        }())

        let total = run.durationSeconds
        _hh = State(initialValue: String(total / 3600))
        _mm = State(initialValue: String((total % 3600) / 60))
        _ss = State(initialValue: String(total % 60))
        _notes = State(initialValue: run.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    TextField("Distance (km)", text: $distanceKm)
                        .keyboardType(.decimalPad)
                    Text("km").foregroundStyle(.secondary)
                }
                Section("Duration (hh:mm:ss)") {
                    HStack(spacing: 6) {
                        TextField("hh", text: $hh)
                            .keyboardType(.numberPad)
                            .frame(width: 52)
                            .multilineTextAlignment(.center)
                        Text(":").monospacedDigit()
                        TextField("mm", text: $mm)
                            .keyboardType(.numberPad)
                            .frame(width: 42)
                            .multilineTextAlignment(.center)
                        Text(":").monospacedDigit()
                        TextField("ss", text: $ss)
                            .keyboardType(.numberPad)
                            .frame(width: 42)
                            .multilineTextAlignment(.center)
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Edit Running")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .brandHeaderSpacer()
        }
    }

    private func save() {
        let dist = Double(distanceKm.replacingOccurrences(of: ",", with: ".")) ?? 0
        let H = Int(hh) ?? 0
        let M = Int(mm) ?? 0
        let S = Int(ss) ?? 0
        let sec = H*3600 + M*60 + S
        guard dist > 0, sec > 0 else { return }

        run.date = date
        run.distanceMeters = dist * 1000
        run.durationSeconds = sec
        run.notes = notes.isEmpty ? nil : notes

        // Recalcular puntos
        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        if settings.persistentModelID == nil { context.insert(settings) }
        run.totalPoints = PointsCalculator.score(running: run, settings: settings)

        do { try context.save() } catch {
            print("Save edit error: \(error)")
        }
        dismiss()
    }
}

@Query private var settingsList: [Settings]
private var useMiles: Bool { settingsList.first?.prefersMiles ?? false }

private func formatDistance(_ km: Double) -> String {
    let value = useMiles ? (km / 1.60934) : km
    let unit = useMiles ? "min/mi" : "min/km"
    return "\(SummaryView.formatNumber(value)) \(unit)"
}

#Preview {
    RunningView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
