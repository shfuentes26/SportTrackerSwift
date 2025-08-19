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
            .frame(height: 180)
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

    // MARK: - Period helpers
    private var start: Date {
        switch mode {
        case .week:  return anchor.startOfWeek
        case .month: return anchor.startOfMonth
        case .year:  return anchor.startOfYear
        }
    }
    private var end: Date {
        switch mode {
        case .week:  return Calendar.current.date(byAdding: .day, value: 7,  to: start)!
        case .month: return Calendar.current.date(byAdding: .month, value: 1, to: start)!
        case .year:  return Calendar.current.date(byAdding: .year, value: 1, to: start)!
        }
    }
    private var isCurrentPeriod: Bool {
        switch mode {
        case .week:  return start == Date().startOfWeek
        case .month: return start == Date().startOfMonth
        case .year:  return start == Date().startOfYear
        }
    }
    private var title: String {
        switch mode {
        case .week:
            let to = Calendar.current.date(byAdding: .day, value: 6, to: start)!
            return DateIntervalFormatter.short(from: start, to: to)
        case .month:
            let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return f.string(from: start)
        case .year:
            let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("yyyy")
            return f.string(from: start)
        }
    }
    private func shift(_ delta: Int) {
        switch mode {
        case .week:  anchor = Calendar.current.date(byAdding: .day,   value: 7*delta, to: anchor)!
        case .month: anchor = Calendar.current.date(byAdding: .month, value: delta,   to: anchor)!
        case .year:  anchor = Calendar.current.date(byAdding: .year,  value: delta,   to: anchor)!
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
        let runs = await fetchRuns(from: start.startOfDay, to: end.startOfDay)
        let cal = Calendar.current

        switch mode {
        case .week:
            var map = Dictionary(uniqueKeysWithValues: (0..<7).map { i in
                let d = cal.date(byAdding: .day, value: i, to: start)!
                return (d.startOfDay, 0.0)
            })
            for r in runs { map[cal.startOfDay(for: r.date), default: 0] += r.distanceKm }
            let ordered = map.keys.sorted().map { d in
                Bucket(label: DateFormatter.shortWeekday(from: d), value: map[d] ?? 0)
            }
            await MainActor.run { buckets = ordered; maxY = max(ordered.map(\.value).max() ?? 0, 0) }

        case .month:
            // Semanas que intersectan el mes [start, end)
            var weekStarts: [Date] = []
            var w = start.startOfWeek
            while w < end {
                weekStarts.append(w)
                w = Calendar.current.date(byAdding: .day, value: 7, to: w)!
            }

            // Suma km por cada semana, recortando los límites al mes
            var result: [Bucket] = []
            for (i, ws) in weekStarts.enumerated() {
                let we = min(Calendar.current.date(byAdding: .day, value: 7, to: ws)!, end)
                let from = max(ws, start)   // recorte por la izquierda (día 1)
                let to   = we               // recorte por la derecha  (fin de mes)

                let sum = runs.reduce(0.0) { acc, r in
                    (r.date >= from && r.date < to) ? acc + r.distanceKm : acc
                }
                result.append(Bucket(label: "W\(i+1)", value: sum)) 
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
            let ordered = (1...12).map { m in
                Bucket(label: DateFormatter.shortMonth(m), value: map[m] ?? 0)
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

// MARK: - Date helpers
private extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var startOfWeek: Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: c) ?? self.startOfDay
    }
    var startOfMonth: Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: c) ?? self.startOfDay
    }
    var startOfYear: Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.year], from: self)
        return cal.date(from: c) ?? self.startOfDay
    }
}

private enum DateIntervalFormatter {
    static func short(from start: Date, to end: Date) -> String {
        let f1 = DateFormatter(); f1.setLocalizedDateFormatFromTemplate("MMM d")
        let f2 = DateFormatter(); f2.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(f1.string(from: start)) – \(f2.string(from: end))"
    }
}

private extension DateFormatter {
    static func shortWeekday(from date: Date) -> String {
        let idx = Calendar.current.component(.weekday, from: date) - 1
        return Calendar.current.shortWeekdaySymbols[idx]   // respeta la localización
    }
    static func shortMonth(_ m: Int) -> String {
        let i = max(0, min(11, m - 1))
        return Calendar.current.shortMonthSymbols[i]
    }
}

