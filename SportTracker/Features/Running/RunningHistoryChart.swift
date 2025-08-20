//
//  RunningHistoryChart.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//
import SwiftUI
import Charts
import SwiftData

// ⬇️ Ajusta el alias al nombre REAL de tu entidad (Run, Running, RunningSession…)
typealias RunEntity = RunningSession

struct RunningHistoryChart: View {
    @Environment(\.modelContext) private var context

    enum Mode: String, CaseIterable, Identifiable { case week, month, year; var id: String { rawValue } }

    @State private var mode: Mode = .week               // Semana por defecto
    @State private var anchor: Date = Date()            // Fecha de referencia para el periodo
    @State private var buckets: [Bucket] = []
    @State private var maxY: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            header

            Chart(buckets) { b in
                BarMark(
                    x: .value("Label", b.label),
                    y: .value("Km", b.value)
                )
                .cornerRadius(6)
                .annotation(position: .top, alignment: .center) {
                    if b.value > 0 {
                        Text(b.value, format: .number.precision(.fractionLength(1)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 160) // ⬅️ más compacto
            .chartYAxis { AxisMarks(position: .leading) }
            .chartYScale(domain: 0...(maxY == 0 ? 1 : maxY * 1.25))
            .animation(.snappy, value: buckets)
        }
        .task { await reload() }
        .onChange(of: mode) { _ in Task { await reload() } }
        .onChange(of: anchor) { _ in Task { await reload() } }
    }

    // MARK: - Header (modo + navegación)
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
                .font(.headline).monospacedDigit()

            Button { shift(+1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(isCurrentPeriod)
        }
        .padding(.horizontal)
    }

    // MARK: - Period helpers (Week -> Monday-first)
    private var start: Date {
        switch mode {
        case .week:  return anchor.RHC_startOfWeekEN   // Monday 00:00
        case .month: return anchor.RHC_startOfMonthEN
        case .year:  return anchor.RHC_startOfYearEN
        }
    }
    private var end: Date {
        switch mode {
        case .week:  return Calendar.RHC_enUSPOSIX.date(byAdding: .day,   value: 7, to: start)! // exclusive
        case .month: return Calendar.RHC_enUSPOSIX.date(byAdding: .month, value: 1, to: start)!
        case .year:  return Calendar.RHC_enUSPOSIX.date(byAdding: .year,  value: 1, to: start)!
        }
    }
    private var isCurrentPeriod: Bool {
        switch mode {
        case .week:  return start == Date().RHC_startOfWeekEN
        case .month: return start == Date().RHC_startOfMonthEN
        case .year:  return start == Date().RHC_startOfYearEN
        }
    }
    private var title: String {
        switch mode {
        case .week:
            return RHC_weekTitle(from: start, toExclusive: end) // “Aug 18 – Aug 24”
        case .month:
            let f = DateFormatter(); f.locale = .RHC_enUSPOSIX; f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return f.string(from: start)
        case .year:
            let f = DateFormatter(); f.locale = .RHC_enUSPOSIX; f.setLocalizedDateFormatFromTemplate("yyyy")
            return f.string(from: start)
        }
    }
    private func shift(_ delta: Int) {
        switch mode {
        case .week:  anchor = Calendar.RHC_enUSPOSIX.date(byAdding: .day,   value: 7*delta, to: anchor)!
        case .month: anchor = Calendar.RHC_enUSPOSIX.date(byAdding: .month, value: delta,   to: anchor)!
        case .year:  anchor = Calendar.RHC_enUSPOSIX.date(byAdding: .year,  value: delta,   to: anchor)!
        }
    }

    // MARK: - Data
    private func fetchRuns(from: Date, to: Date) async -> [RunEntity] {
        do {
            var desc = FetchDescriptor<RunEntity>(
                predicate: #Predicate { $0.date >= from && $0.date < to }
            )
            desc.sortBy = [SortDescriptor(\RunEntity.date)]
            return try context.fetch(desc)
        } catch {
            print("Fetch error:", error)
            return []
        }
    }

    private func reload() async {
        let runs = await fetchRuns(from: start.RHC_startOfDay, to: end.RHC_startOfDay)
        let cal  = Calendar.RHC_enUSPOSIX

        switch mode {
        case .week:
            // M, Tu, W, Th, F, Sa, Su (Monday-first)
            var map = Dictionary(uniqueKeysWithValues: (0..<7).map { i in
                let d = cal.date(byAdding: .day, value: i, to: start)!
                return (cal.startOfDay(for: d), 0.0)
            })
            for r in runs {
                map[cal.startOfDay(for: r.date), default: 0] += r.distanceKm
            }
            let orderedDates = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
            let ordered = orderedDates.map { d in
                Bucket(label: d.RHC_weekdayLabelEN, value: map[cal.startOfDay(for: d)] ?? 0)
            }
            await MainActor.run { buckets = ordered; maxY = max(ordered.map(\.value).max() ?? 0, 0) }

        case .month:
            // Semanas que intersectan el mes [start, end)
            var weekStarts: [Date] = []
            var ws = start.RHC_startOfWeekEN
            while ws < end {
                weekStarts.append(ws)
                ws = cal.date(byAdding: .day, value: 7, to: ws)!
            }

            // Suma por semana (recortada a los límites del mes) y etiqueta "d1–d2"
            var result: [Bucket] = []
            for ws in weekStarts {
                let we   = min(cal.date(byAdding: .day, value: 7, to: ws)!, end)
                let from = max(ws, start)   // dentro del mes
                let to   = we               // exclusivo

                let sum = runs.reduce(0.0) { acc, r in
                    (r.date >= from && r.date < to) ? acc + r.distanceKm : acc
                }

                let label = weekRangeLabel(from: from, to: to) // puede seguir usando tu helper actual
                result.append(Bucket(label: label, value: sum))
            }

            await MainActor.run {
                buckets = result
                maxY = result.map(\.value).max() ?? 0
            }

        case .year:
            var map = Dictionary(uniqueKeysWithValues: (1...12).map { (month: $0, km: 0.0) })
            for r in runs {
                let m = cal.component(.month, from: r.date)
                map[m, default: 0] += r.distanceKm
            }
            let df = DateFormatter(); df.locale = .RHC_enUSPOSIX
            let monthLabels = df.shortMonthSymbols ?? ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            let ordered = (1...12).map { m in
                Bucket(label: monthLabels[max(0, min(11, m - 1))], value: map[m] ?? 0)
            }
            await MainActor.run { buckets = ordered; maxY = max(ordered.map(\.value).max() ?? 0, 0) }
        }
    }

    struct Bucket: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let value: Double
    }
}

// MARK: - Monday-first helpers (EN) — solo para Running
fileprivate extension Locale { static let RHC_enUSPOSIX = Locale(identifier: "en_US_POSIX") }

fileprivate extension Calendar {
    static var RHC_enUSPOSIX: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.locale = .RHC_enUSPOSIX
        c.firstWeekday = 2           // Monday
        c.minimumDaysInFirstWeek = 4
        return c
    }()
    func RHC_startOfWeek(for d: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return date(from: comps) ?? startOfDay(for: d)
    }
}

fileprivate extension Date {
    var RHC_startOfDay: Date { Calendar.RHC_enUSPOSIX.startOfDay(for: self) }
    var RHC_startOfWeekEN: Date { Calendar.RHC_enUSPOSIX.RHC_startOfWeek(for: self) }
    var RHC_startOfMonthEN: Date {
        Calendar.RHC_enUSPOSIX.date(from: Calendar.RHC_enUSPOSIX.dateComponents([.year, .month], from: self)) ?? self
    }
    var RHC_startOfYearEN: Date {
        Calendar.RHC_enUSPOSIX.date(from: Calendar.RHC_enUSPOSIX.dateComponents([.year], from: self)) ?? self
    }
    var RHC_weekdayLabelEN: String {
        switch Calendar.RHC_enUSPOSIX.component(.weekday, from: self) {
        case 2: return "M"
        case 3: return "Tu"
        case 4: return "W"
        case 5: return "Th"
        case 6: return "F"
        case 7: return "Sa"
        default: return "Su"
        }
    }
}

// “Aug 18 – Aug 24”
fileprivate func RHC_weekTitle(from start: Date, toExclusive end: Date) -> String {
    let incEnd = Calendar.RHC_enUSPOSIX.date(byAdding: .day, value: -1, to: end) ?? end
    let f = DateFormatter(); f.locale = .RHC_enUSPOSIX; f.setLocalizedDateFormatFromTemplate("MMM d")
    return "\(f.string(from: start)) – \(f.string(from: incEnd))"
}

// Label like "18–24" for a week range [from, to)
fileprivate func weekRangeLabel(from: Date, to: Date) -> String {
    let cal = Calendar.RHC_enUSPOSIX
    let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: to) ?? to
    let s = cal.component(.day, from: from)
    let e = cal.component(.day, from: inclusiveEnd)
    return "\(s)–\(e)"
}


// Helpers existentes que ya usabas (mes/semanas dentro del mes) pueden seguir igual.
// RunningView no requiere cambios. :contentReference[oaicite:1]{index=1}
