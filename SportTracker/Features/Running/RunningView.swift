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
                                                let badges = RunRecords.badges(for: r, among: runs, top: 3, minFactor: 1.0, preferAbsoluteOverYear: false)
                                                if !badges.isEmpty {
                                                        RecordBadgesRow(badges: badges)
                                                            .padding(.leading, 4)
                                                    }
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
    
    // MARK: - Record Badges
    private struct RecordBadgesRow: View {
        let badges: [RecordBadgeModel]
        var body: some View {
            HStack(spacing: 4) {
                ForEach(badges) { b in
                    ZStack {
                        Circle()
                            .fill(color(for: b))
                            .frame(width: 18, height: 18)
                        Text(text(for: b))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        private func color(for b: RecordBadgeModel) -> Color {
            switch b.kind {
            case .absolute(let rank, _), .yearly(let rank, _, _):
                switch rank {
                case 1: return .yellow
                case 2: return .gray
                case 3: return .brown
                default: return .secondary
                }
            }
        }
        private func text(for b: RecordBadgeModel) -> String {
            switch b.kind {
            case .absolute:                   return "BR"
            case .yearly(_, let year, _):    return String(year % 100)
            }
        }
    }


    
    
    // MARK: - Badge VM y ranking
    private enum BadgeKind {
        case absolute(rank: Int, bucketKm: Double)
        case yearly(rank: Int, year: Int, bucketKm: Double)
    }
    private struct BadgeVM: Identifiable {
        let id = UUID()
        let kind: BadgeKind
    }

    private func computeRunBadges(for run: RunningSession, among runs: [RunningSession]) -> [BadgeVM] {
        let km = run.distanceMeters / 1000.0
        guard let bucket = bucketKm(for: km) else { return [] }

        // Conjunto por bucket usando la MISMA asignación para todos
        let sameBucket = runs.filter { r in
            let rkm = r.distanceMeters / 1000.0
            return bucketKm(for: rkm) == bucket
        }

        // Orden estable: mejor pace -> menor duración -> fecha más reciente
        let sortedAbs = sameBucket.sorted {
            let p0 = paceSecPerKm($0), p1 = paceSecPerKm($1)
            if p0 != p1 { return p0 < p1 }
            if $0.durationSeconds != $1.durationSeconds { return $0.durationSeconds < $1.durationSeconds }
            return $0.date > $1.date
        }

        var badges: [BadgeVM] = []

        // Rank absoluto (top 3)
        if let idx = sortedAbs.firstIndex(where: { $0.id == run.id }) {
            let rank = idx + 1
            if rank <= 3 {
                badges.append(.init(kind: .absolute(rank: rank, bucketKm: bucket)))
            }
        }

        // Rank anual (top 3 dentro del año del propio run)
        let year = Calendar.current.component(.year, from: run.date)
        let sameYear = sortedAbs.filter { Calendar.current.component(.year, from: $0.date) == year }
        if let idxY = sameYear.firstIndex(where: { $0.id == run.id }) {
            let rankY = idxY + 1
            if rankY <= 3 {
                badges.append(.init(kind: .yearly(rank: rankY, year: year, bucketKm: bucket)))
            }
        }

        return badges
    }


    private func paceSecPerKm(_ r: RunningSession) -> Double {
        max(Double(r.durationSeconds) / max(r.distanceMeters / 1000.0, 0.001), 0)
    }
    // Asigna el bucket “máximo ≤ distancia del run”.
    // Ej: 5.5 -> 5.0 ; 10.3 -> 10.0 ; 0.95 -> nil (no alcanza 1K)
    private func bucketKm(for km: Double) -> Double? {
        let buckets: [Double] = [1.0, 3.0, 5.0, 10.0, 21.0975, 42.195]
        // Puedes exigir que “al menos” se alcance el 95% del bucket para cubrir GPS/errores manuales:
        let minFactor = 1.0
        let candidates = buckets.filter { km >= $0 * minFactor }
        return candidates.max() // mayor bucket que cumple
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
