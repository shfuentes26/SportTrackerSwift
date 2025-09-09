import SwiftUI
import SwiftData

struct SummaryView: View {
    @Query(sort: [SortDescriptor(\RunningSession.date, order: .reverse)])
    private var runs: [RunningSession]
    @Query(sort: [SortDescriptor(\StrengthSession.date, order: .reverse)])
    private var gyms: [StrengthSession]
    @Query private var settingsList: [Settings]
    private var useMiles: Bool { settingsList.first?.prefersMiles ?? false }
    private var usePounds: Bool { settingsList.first?.prefersPounds ?? false }
    @Query private var runningGoals: [RunningGoal]
    @Query private var gymGoals: [GymGoal]

    // Deep-link a cada pestaña del editor
    @State private var goToRunningGoal = false
    @State private var goToGymGoal = false
    
    @Environment(\.modelContext) private var context
    @State private var editingRun: RunningSession? = nil
    @State private var editingGym: StrengthSession? = nil
    @State private var goToPoints = false

    init() {}

    private let rowIconWidth: CGFloat = 22

    var body: some View {
        NavigationStack {
            List {
                goalsCardSection
                if combinedItems.isEmpty {
                    ContentUnavailableView("There are no trainings yet", systemImage: "calendar.badge.clock")
                } else {
                    Section("Past Trainings") {
                        ForEach(combinedItems) { row in
                            switch row {
                            case .run(let r):
                                NavigationLink {
                                    TrainingDetailView(item: .running(r))
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "figure.run")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .frame(width: rowIconWidth, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Running • \(Self.formatDate(r.date))").font(.headline)
                                            Text("\(UnitFormatters.distance(r.distanceKm, useMiles: useMiles)) • \(UnitFormatters.pace(secondsPerKm: r.paceSecondsPerKm, useMiles: useMiles))")
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int(r.totalPoints)) pts")
                                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) { deleteRun(r) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { editingRun = r } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                }

                            case .gym(let s):
                                NavigationLink {
                                    TrainingDetailView(item: .gym(s))
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "dumbbell.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .frame(width: rowIconWidth, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Gym • \(Self.formatDate(s.date))").font(.headline)
                                            Text(gymDetails(s))
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int(s.totalPoints)) pts")
                                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) { deleteGym(s) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { editingGym = s } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }

                }

            }
            // Links ocultos para navegar sin chevron y hacia la pestaña adecuada
            .background(
                Group {
                    NavigationLink("", isActive: $goToRunningGoal) {
                        GoalsSettingsView(selectedTab: .running)
                    }.hidden()
                    NavigationLink("", isActive: $goToGymGoal) {
                        GoalsSettingsView(selectedTab: .gym)
                    }.hidden()
                }
            )
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PointsInsightsView(runs: runs, gyms: gyms)
                    } label: {
                        WeeklyPointsPillView(runs: runs, gyms: gyms)
                    }
                    .buttonStyle(.plain)
                }
            }
            .brandHeaderSpacer()
            .sheet(item: $editingRun) { run in
                EditRunningSheet(run: run)
            }
            .sheet(item: $editingGym) { session in
                EditGymSheet(session: session)
            }
        }
        .brandNavBar()
    }

    // MARK: - GOALS CARD

    @ViewBuilder
    private var goalsCardSection: some View {
        let rg = runningGoals.first
        let gg = gymGoals.first

        if (rg?.weeklyKilometers ?? 0) <= 0 && (gg?.totalWeeklyTarget ?? 0) <= 0 {
            Section {
                Button { goToRunningGoal = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "target").font(.title2)
                        VStack(alignment: .leading) {
                            Text("Create a goal").font(.headline)
                            Text("Track weekly progress for Running and Gym")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.yellow.opacity(0.18))
                )
            }
        } else {
            Section("Goals") {
                if let rg = rg, rg.weeklyKilometers > 0,
                   let gg = gg, gg.totalWeeklyTarget > 0 {

                    let kmThisWeek = runningKilometersThisWeek
                    let runningProgress = min(kmThisWeek / rg.weeklyKilometers, 1)

                    let counts = gymCountsThisWeek()
                    let met = min(counts.chestBack, gg.targetChestBack)
                           + min(counts.arms, gg.targetArms)
                           + min(counts.legs, gg.targetLegs)
                           + min(counts.core, gg.targetCore)
                    let total = max(gg.totalWeeklyTarget, 1)
                    let gymProgress = Double(met) / Double(total)
                    let legend = "CB \(counts.chestBack)/\(gg.targetChestBack) • Arms \(counts.arms)/\(gg.targetArms) • Legs \(counts.legs)/\(gg.targetLegs) • Core \(counts.core)/\(gg.targetCore)"

                    HStack(alignment: .top, spacing: 16) {
                        Button { goToRunningGoal = true } label: {
                            GoalRingView(
                                title: "Running",
                                progress: runningProgress,
                                subtitle: "\(Self.formatNumber(kmThisWeek)) / \(Self.formatNumber(rg.weeklyKilometers)) km"
                            )
                            .frame(maxWidth: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button { goToGymGoal = true } label: {
                            GoalRingView(
                                title: "Gym",
                                progress: gymProgress,
                                subtitle: legend
                            )
                            .frame(maxWidth: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)

                } else if let rg = rg, rg.weeklyKilometers > 0 {
                    let kmThisWeek = runningKilometersThisWeek
                    let p = min(kmThisWeek / rg.weeklyKilometers, 1)
                    Button { goToRunningGoal = true } label: {
                        GoalRingView(
                            title: "Running",
                            progress: p,
                            subtitle: "\(Self.formatNumber(kmThisWeek)) / \(Self.formatNumber(rg.weeklyKilometers)) km"
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                } else if let gg = gg, gg.totalWeeklyTarget > 0 {
                    let counts = gymCountsThisWeek()
                    let met = min(counts.chestBack, gg.targetChestBack)
                           + min(counts.arms, gg.targetArms)
                           + min(counts.legs, gg.targetLegs)
                           + min(counts.core, gg.targetCore)
                    let total = max(gg.totalWeeklyTarget, 1)
                    let p = Double(met) / Double(total)
                    let legend = "CB \(counts.chestBack)/\(gg.targetChestBack) • Arms \(counts.arms)/\(gg.targetArms) • Legs \(counts.legs)/\(gg.targetLegs) • Core \(counts.core)/\(gg.targetCore)"

                    Button { goToGymGoal = true } label: {
                        GoalRingView(title: "Gym", progress: p, subtitle: legend)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers de semana/formatos

    private var weekInterval: DateInterval {
        var cal = Calendar.current
        cal.firstWeekday = 2 // 1=Sunday, 2=Monday
        if let di = cal.dateInterval(of: .weekOfYear, for: Date()) {
            return di
        }
        let start = cal.startOfDay(for: Date())
        return DateInterval(start: start, duration: 7*24*3600)
    }

    private var runningKilometersThisWeek: Double {
        let di = weekInterval
        let weekRuns = runs.filter { di.contains($0.date) }
        return weekRuns.reduce(0) { $0 + $1.distanceKm }
    }

    private func gymCountsThisWeek() -> (chestBack: Int, arms: Int, legs: Int, core: Int) {
        let di = weekInterval
        let sessions = gyms.filter { di.contains($0.date) }
        var cb = 0, arms = 0, legs = 0, core = 0
        for s in sessions {
            // ✅ usar el proxy no opcional
            let groups = Set(s.sets.map { $0.exerciseResolved.muscleGroup })
            if groups.contains(.chestBack) { cb += 1 }
            if groups.contains(.arms) { arms += 1 }
            if groups.contains(.legs) { legs += 1 }
            if groups.contains(.core) { core += 1 }
        }
        return (cb, arms, legs, core)
    }

    private var pastItems: [PastItem] {
        
        let runItems = runs.map { r in
            PastItem(id: "run-\(r.id.uuidString)",
                     date: r.date,
                     icon: "figure.run",
                     title: "Running • \(Self.formatDate(r.date))",
                     subtitle: "\(UnitFormatters.distance(r.distanceKm, useMiles: useMiles)) • \(UnitFormatters.pace(secondsPerKm: r.paceSecondsPerKm, useMiles: useMiles))",
                     trailing: "\(Int(r.totalPoints)) pts")
        }
        let gymItems = gyms.map { s in
            PastItem(id: "gym-\(s.id.uuidString)",
                     date: s.date,
                     icon: "dumbbell.fill",
                     title: "Gym • \(Self.formatDate(s.date))",
                     subtitle: gymDetails(s),
                     trailing: "\(Int(s.totalPoints)) pts")
        }
        return (runItems + gymItems).sorted { $0.date > $1.date }
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
                // ✅ usar el proxy
                return "\(set.exerciseResolved.name) \(reps)\(w)"
            }
        var line = items.joined(separator: " • ")
        if s.sets.count > 3 { line += " …" }
        return line
    }

    struct PastItem: Identifiable {
        let id: String
        let date: Date
        let icon: String
        let title: String
        let subtitle: String
        let trailing: String
    }

    // MARK: - Formatters
    static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func formatNumber(_ x: Double) -> String {
        let nf = NumberFormatter()
        nf.maximumFractionDigits = 1
        nf.minimumFractionDigits = 0
        return nf.string(from: NSNumber(value: x)) ?? String(format: "%.1f", x)
    }

    static func formatPace(_ secPerKm: Double) -> String {
        guard secPerKm > 0 else { return "--" }
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d min/km", m, s)
    }

    private func distString(_ km: Double) -> String {
        let value = useMiles ? (km / 1.60934) : km
        let unit  = useMiles ? "mi" : "km"
        return "\(SummaryView.formatNumber(value)) \(unit)"
    }

    private func paceString(_ secondsPerKm: Double) -> String {
        let secsDouble = useMiles ? (secondsPerKm * 1.60934) : secondsPerKm
        let secs = Int(round(secsDouble))
        let mm = secs / 60
        let ss = secs % 60
        return String(format: "%d:%02d %@", mm, ss, useMiles ? "/mi" : "/km")
    }
    
    private enum PastRow: Identifiable {
        case run(RunningSession)
        case gym(StrengthSession)

        var id: String {
            switch self {
            case .run(let r): return "run-\(r.id.uuidString)"
            case .gym(let s): return "gym-\(s.id.uuidString)"
            }
        }
        var date: Date {
            switch self {
            case .run(let r): return r.date
            case .gym(let s): return s.date
            }
        }
    }
    private var combinedItems: [PastRow] {
        (runs.map(PastRow.run) + gyms.map(PastRow.gym)).sorted { $0.date > $1.date }
    }

    @MainActor private func deleteRun(_ r: RunningSession) {
        context.delete(r); try? context.save()
    }
    @MainActor private func deleteGym(_ s: StrengthSession) {
        context.delete(s); try? context.save()
    }

}

// Editor rápido para Running (igual patrón que en RunningView)
private struct EditRunningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State var run: RunningSession

    @State private var date: Date
    @State private var distanceKm: String
    @State private var hh: String
    @State private var mm: String
    @State private var ss: String
    @State private var notes: String

    init(run: RunningSession) {
        _run = State(initialValue: run)
        _date = State(initialValue: run.date)
        _distanceKm = State(initialValue: SummaryView.formatNumber(run.distanceKm))
        let sec = run.durationSeconds
        _hh = State(initialValue: String(sec/3600))
        _mm = State(initialValue: String((sec%3600)/60))
        _ss = State(initialValue: String(sec%60))
        _notes = State(initialValue: run.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    TextField("Distance (km)", text: $distanceKm).keyboardType(.decimalPad)
                    Text("km").foregroundStyle(.secondary)
                }
                Section("Duration (hh:mm:ss)") {
                    HStack(spacing: 6) {
                        TextField("hh", text: $hh).keyboardType(.numberPad).frame(width: 42).multilineTextAlignment(.center)
                        Text(":")
                        TextField("mm", text: $mm).keyboardType(.numberPad).frame(width: 42).multilineTextAlignment(.center)
                        Text(":")
                        TextField("ss", text: $ss).keyboardType(.numberPad).frame(width: 42).multilineTextAlignment(.center)
                    }.monospacedDigit()
                }
                Section("Notes") { TextField("Optional", text: $notes, axis: .vertical) }
            }
            .navigationTitle("Edit Running")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        print("[SummaryView]save is called")
        let dist = Double(distanceKm.replacingOccurrences(of: ",", with: ".")) ?? 0
        let H = Int(hh) ?? 0, M = Int(mm) ?? 0, S = Int(ss) ?? 0
        let sec = H*3600 + M*60 + S
        guard dist > 0, sec > 0 else { return }

        run.date = date
        run.distanceMeters = dist * 1000
        run.durationSeconds = sec
        run.notes = notes.isEmpty ? nil : notes

        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        if settings.persistentModelID == nil { context.insert(settings) }
        let km = dist
        let minutes = Double(sec)/60.0
        let paceSecPerKm = Double(sec)/max(km, 0.001)
        let distancePts = km * settings.runningDistanceFactor
        let timePts = minutes * settings.runningTimeFactor
        let paceBonus = max(0, (settings.runningPaceBaselineSecPerKm - paceSecPerKm)/settings.runningPaceBaselineSecPerKm) * settings.runningPaceFactor
        run.totalPoints = distancePts + timePts + paceBonus

        try? context.save()
        dismiss()
    }
}

