//
//  GymHistoryChart.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/20/25.
//
import SwiftUI
import Charts
import SwiftData

// Make sure this enum exists only once in the project.
enum GymGroup: String, CaseIterable, Identifiable {
    case chestBack = "Chest/Back"
    case arms      = "Arms"
    case legs      = "Legs"
    case core      = "Core"
    var id: String { rawValue }
}

// Fixed palette so colors stay consistent across tabs
struct GymChartPalette {
    static let domain = [
        GymGroup.chestBack.rawValue,
        GymGroup.arms.rawValue,
        GymGroup.legs.rawValue,
        GymGroup.core.rawValue
    ]
    static let colors: [Color] = [.blue, .orange, .green, .purple]
}

private struct StackPoint: Identifiable {
    let id = UUID()
    let label: String       // X bucket (day label, week range or month)
    let group: GymGroup
    let value: Int
}

struct GymHistoryChart: View {
    enum Mode: String, CaseIterable, Identifiable { case week, month, year; var id: String { rawValue } }

    let sessions: [StrengthSession]

    @State private var mode: Mode = .week
    @State private var anchor: Date = Date()

    @State private var data: [StackPoint] = []
    @State private var xDomain: [String] = []
    @State private var maxY: Double = 0

    private let metric: Metric = .uniqueExercises
    private enum Metric { case uniqueExercises, sets, points }

    var body: some View {
        VStack(spacing: 10) {
            // Header a todo el ancho
            header
                .frame(maxWidth: .infinity, alignment: .leading)

            // Chart a todo el ancho
            Chart(data) { dp in
                BarMark(
                    x: .value("Bucket", dp.label),
                    y: .value("Value", dp.value)
                )
                .foregroundStyle(by: .value("Group", dp.group.rawValue))
            }
            .chartXScale(domain: xDomain)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartYScale(domain: 0...(maxY == 0 ? 1 : maxY * 1.25))
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .chartForegroundStyleScale(domain: GymChartPalette.domain, range: GymChartPalette.colors)
            .frame(height: 160)
            .frame(maxWidth: .infinity)      // ⬅️ fuerza el ancho
        }
        .padding(.vertical, 4)
        // .padding(.horizontal)
        .onAppear { reload() }
        .onChange(of: mode) { _ in reload() }
        .onChange(of: anchor) { _ in reload() }
        // Después
        .task(id: sessions.map(\.id)) {
            reload()
        }
        .task(id: sessions.flatMap { $0.sets.map(\.id) }) {
            reload()
        }
        .animation(.snappy, value: mode)
        .animation(.snappy, value: anchor)
    }

    // MARK: Header (picker + chevrons + period title)
    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $mode) {
                Text("Week").tag(Mode.week)
                Text("Month").tag(Mode.month)
                Text("Year").tag(Mode.year)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Spacer()

            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)

            Text(title)
                .font(.headline)
                .monospacedDigit()

            Button { shift(+1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(isCurrentPeriod)
        }
        .padding(.horizontal, 16)   // ✅ igual que Running
        // ⛔️ quita cualquier `.padding(.top, ...)` aquí
    }


    // MARK: Period helpers
    private var start: Date {
        switch mode {
        case .week:  return anchor.startOfWeekEN
        case .month: return anchor.startOfMonthEN
        case .year:  return anchor.startOfYearEN
        }
    }
    private var end: Date {
        let c = Calendar.enUSPOSIX
        switch mode {
        case .week:  return c.date(byAdding: .day,   value: 7, to: start)!
        case .month: return c.date(byAdding: .month, value: 1, to: start)!
        case .year:  return c.date(byAdding: .year,  value: 1, to: start)!
        }
    }
    private var isCurrentPeriod: Bool {
        switch mode {
        case .week:  return start == Date().startOfWeekEN
        case .month: return start == Date().startOfMonthEN
        case .year:  return start == Date().startOfYearEN
        }
    }
    private var title: String {
        switch mode {
        case .week:  return weekTitle(from: start, toExclusive: end)            // “Aug 18 – Aug 24”
        case .month:
            let f = DateFormatter(); f.locale = .enUSPOSIX; f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return f.string(from: start)
        case .year:
            let f = DateFormatter(); f.locale = .enUSPOSIX; f.setLocalizedDateFormatFromTemplate("yyyy")
            return f.string(from: start)
        }
    }
    private func shift(_ delta: Int) {
        let c = Calendar.enUSPOSIX
        switch mode {
        case .week:  anchor = c.date(byAdding: .day,   value: 7*delta, to: anchor)!
        case .month: anchor = c.date(byAdding: .month, value: delta,   to: anchor)!
        case .year:  anchor = c.date(byAdding: .year,  value: delta,   to: anchor)!
        }
    }

    // MARK: Data aggregation
    private func reload() {
        let c = Calendar.enUSPOSIX
        let from = start
        let to = end
        let inRange = sessions.filter { $0.date >= from && $0.date < to }

        switch mode {
        case .week:
            let labels: [String] = (0..<7).map { i in
                let d = c.date(byAdding: .day, value: i, to: from)!
                return d.weekdayLabelEN // M, Tu, W, Th, F, Sa, Su
            }
            xDomain = labels

            var map: [String: [GymGroup: Int]] = Dictionary(uniqueKeysWithValues: labels.map { ($0, [:]) })

            for sess in inRange {
                let key = c.startOfDay(for: sess.date).weekdayLabelEN
                switch metric {
                case .uniqueExercises:
                    var seen: [GymGroup: Set<UUID>] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { seen[g, default: []].insert(set.exercise.id) } }
                    for (g, uniq) in seen { map[key]?[g, default: 0] += uniq.count }
                case .sets:
                    var counts: [GymGroup: Int] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { counts[g, default: 0] += 1 } }
                    for (g, c) in counts { map[key]?[g, default: 0] += c }
                case .points:
                    var pts: [GymGroup: Int] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { pts[g, default: 0] += max(1, set.reps) } }
                    for (g, p) in pts { map[key]?[g, default: 0] += p }
                }
            }

            data = labels.flatMap { label in
                (map[label] ?? [:]).sorted { $0.key.rawValue < $1.key.rawValue }.map { (g, v) in
                    StackPoint(label: label, group: g, value: v)
                }
            }
            maxY = data.reduce(into: [String: Int]()) { acc, dp in acc[dp.label, default: 0] += dp.value }.values.max().map(Double.init) ?? 0

        case .month:
            // Week buckets inside the month (clamped to the month)
            var weekStarts: [Date] = []
            var ws = from.startOfWeekEN
            while ws < to { weekStarts.append(ws); ws = c.date(byAdding: .day, value: 7, to: ws)! }

            xDomain = weekStarts.map {
                let we = min(c.date(byAdding: .day, value: 7, to: $0)!, to)
                return weekRangeLabel(from: max($0, from), to: we)
            }

            var map: [String: [GymGroup: Int]] = Dictionary(uniqueKeysWithValues: xDomain.map { ($0, [:]) })

            for sess in inRange {
                let ws = c.startOfWeek(for: sess.date)
                let we = min(c.date(byAdding: .day, value: 7, to: ws)!, to)
                let label = weekRangeLabel(from: max(ws, from), to: we)
                switch metric {
                case .uniqueExercises:
                    var seen: [GymGroup: Set<UUID>] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { seen[g, default: []].insert(set.exercise.id) } }
                    for (g, uniq) in seen { map[label]?[g, default: 0] += uniq.count }
                case .sets:
                    var counts: [GymGroup: Int] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { counts[g, default: 0] += 1 } }
                    for (g, c) in counts { map[label]?[g, default: 0] += c }
                case .points:
                    var pts: [GymGroup: Int] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { pts[g, default: 0] += max(1, set.reps) } }
                    for (g, p) in pts { map[label]?[g, default: 0] += p }
                }
            }

            data = xDomain.flatMap { label in
                (map[label] ?? [:]).sorted { $0.key.rawValue < $1.key.rawValue }.map { (g, v) in
                    StackPoint(label: label, group: g, value: v)
                }
            }
            maxY = data.reduce(into: [String: Int]()) { acc, dp in acc[dp.label, default: 0] += dp.value }.values.max().map(Double.init) ?? 0

        case .year:
            var df = DateFormatter(); df.locale = .enUSPOSIX
            let months: [String] = df.shortMonthSymbols ?? ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            xDomain = months

            var map: [String: [GymGroup: Int]] = Dictionary(uniqueKeysWithValues: months.map { ($0, [:]) })

            for sess in inRange {
                let m = c.component(.month, from: sess.date)
                let label = months[max(0, min(11, m - 1))]
                switch metric {
                case .uniqueExercises:
                    var seen: [GymGroup: Set<UUID>] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { seen[g, default: []].insert(set.exercise.id) } }
                    for (g, uniq) in seen { map[label]?[g, default: 0] += uniq.count }
                case .sets:
                    var counts: [GymGroup: Int] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { counts[g, default: 0] += 1 } }
                    for (g, c) in counts { map[label]?[g, default: 0] += c }
                case .points:
                    var pts: [GymGroup: Int] = [:]
                    for set in sess.sets { if let g = mapGroup(set.exercise.muscleGroup) { pts[g, default: 0] += max(1, set.reps) } }
                    for (g, p) in pts { map[label]?[g, default: 0] += p }
                }
            }

            data = months.flatMap { label in
                (map[label] ?? [:]).sorted { $0.key.rawValue < $1.key.rawValue }.map { (g, v) in
                    StackPoint(label: label, group: g, value: v)
                }
            }
            maxY = data.reduce(into: [String: Int]()) { acc, dp in acc[dp.label, default: 0] += dp.value }.values.max().map(Double.init) ?? 0
        }
    }

    private func mapGroup(_ g: MuscleGroup) -> GymGroup? {
        switch g {
        case .core:      return .core
        case .chestBack: return .chestBack
        case .arms:      return .arms
        case .legs:      return .legs
        default:         return nil
        }
    }
}

// MARK: - Date helpers (EN, Monday-first)
private extension Locale { static let enUSPOSIX = Locale(identifier: "en_US_POSIX") }

private extension Calendar {
    static var enUSPOSIX: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = .enUSPOSIX
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()
    func startOfWeek(for d: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return date(from: comps) ?? d
    }
}

private extension Date {
    var startOfWeekEN: Date  { Calendar.enUSPOSIX.startOfWeek(for: self) }
    var startOfMonthEN: Date { Calendar.enUSPOSIX.date(from: Calendar.enUSPOSIX.dateComponents([.year, .month], from: self)) ?? self }
    var startOfYearEN: Date  { Calendar.enUSPOSIX.date(from: Calendar.enUSPOSIX.dateComponents([.year], from: self)) ?? self }
    var weekdayLabelEN: String {
        switch Calendar.enUSPOSIX.component(.weekday, from: self) {
        case 2: return "M"; case 3: return "Tu"; case 4: return "W"
        case 5: return "Th"; case 6: return "F"; case 7: return "Sa"
        default: return "Su"
        }
    }
}

// “Aug 18 – Aug 24”
private func weekTitle(from start: Date, toExclusive end: Date) -> String {
    let incEnd = Calendar.enUSPOSIX.date(byAdding: .day, value: -1, to: end) ?? end
    let f = DateFormatter(); f.locale = .enUSPOSIX; f.setLocalizedDateFormatFromTemplate("MMM d")
    return "\(f.string(from: start)) – \(f.string(from: incEnd))"
}

// “18–24”
private func weekRangeLabel(from: Date, to: Date) -> String {
    let incEnd = Calendar.enUSPOSIX.date(byAdding: .day, value: -1, to: to) ?? to
    let s = Calendar.enUSPOSIX.component(.day, from: from)
    let e = Calendar.enUSPOSIX.component(.day, from: incEnd)
    return "\(s)–\(e)"
}
