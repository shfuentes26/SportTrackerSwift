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

    init() {}

    private let rowIconWidth: CGFloat = 22

    var body: some View {
        NavigationStack {
            List {
                goalsCardSection

                if pastItems.isEmpty {
                    ContentUnavailableView("There are no trainings yet", systemImage: "calendar.badge.clock")
                } else {
                    Section("Past Trainings") {
                        ForEach(pastItems) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: rowIconWidth, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(item.trailing)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
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
            .brandHeaderSpacer()
        }
    }

    // MARK: - GOALS CARD

    @ViewBuilder
    private var goalsCardSection: some View {
        let rg = runningGoals.first
        let gg = gymGoals.first

        // No goals todavía → tarjeta "Create a goal"
        if (rg?.weeklyKilometers ?? 0) <= 0 && (gg?.totalWeeklyTarget ?? 0) <= 0 {
            Section {
                Button { goToRunningGoal = true } label: {   // abrimos en pestaña Running por defecto
                    HStack(spacing: 12) {
                        Image(systemName: "target").font(.title2)
                        VStack(alignment: .leading) {
                            Text("Create a goal").font(.headline)
                            Text("Track weekly progress for Running and Gym")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(                      // <— fondo amarillo claro SOLO para esta tarjeta
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.yellow.opacity(0.18))
                    )
            }
        } else {
            Section("Goals") {
                // Ambos objetivos → dos anillos clicables (cada uno navega a su detalle)
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
                    // Solo Running
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
                    // Solo Gym
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
        let cal = Calendar.current
        if let di = cal.dateInterval(of: .weekOfYear, for: Date()) { return di }
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
            let groups = Set(s.sets.map { $0.exercise.muscleGroup })
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
                return "\(set.exercise.name) \(reps)\(w)"
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
}

#Preview {
    SummaryView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
