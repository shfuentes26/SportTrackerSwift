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
    
    @State private var runFilter: RunDistanceFilter = .all
    private var filteredRuns: [RunningSession] {
        runs.filter { run in
            runFilter.allows(distanceMeters: run.distanceMeters)
        }
    }


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
                        if filteredRuns.isEmpty {
                            ContentUnavailableView(
                                "There are no running trainings yet",
                                systemImage: "figure.run"
                            )
                        } else {
                            Section("Past Trainings") {
                                ForEach(filteredRuns) { r in
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
            .onAppear { AnalyticsService.logScreen(name: "Running") }
            .navigationBarTitleDisplayMode(.large)          // ← nuevo
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                       Menu {
                           Picker("Distance", selection: $runFilter) {
                               Text("All").tag(RunDistanceFilter.all)
                               Text("1K").tag(RunDistanceFilter.k1)
                               Text("3K").tag(RunDistanceFilter.k3)
                               Text("5K").tag(RunDistanceFilter.k5)
                               Text("10K").tag(RunDistanceFilter.k10)
                               Text("Half").tag(RunDistanceFilter.half)
                               Text("Marathon").tag(RunDistanceFilter.marathon)
                           }
                       } label: {
                           // Igual estilo que Exercises: icono + título actual
                           Label(runFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                       }
                   }
               }
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
