//
//  GymExerciseInsightsView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/1/25.
//
import SwiftUI
import SwiftData
import Charts

struct GymExerciseInsightsView: View {
    typealias Period = GymExerciseInsightsVM.Period

    @StateObject private var vm: GymExerciseInsightsVM

    let exerciseName: String
    let usePounds: Bool

    @State private var period: Period = .ytd
    @State private var selPoint: (date: Date, value: Double)? = nil

    private struct LocalCallout: View {
        let title: String
        let subtitle: String
        var body: some View {
            VStack(spacing: 2) {
                Text(title).font(.caption).fontWeight(.semibold).monospacedDigit()
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.4), lineWidth: 1))
        }
    }

    init(exercise: Exercise, currentSession: StrengthSession, usePounds: Bool, context: ModelContext) {
        _vm = StateObject(wrappedValue: GymExerciseInsightsVM(context: context,
                                                              exercise: exercise,
                                                              refDate: currentSession.date))
        self.exerciseName = exercise.name
        self.usePounds = usePounds
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 6) {
                    Text(exerciseName).font(.title3).bold()
                    Text(vm.isWeighted ? labelForWeighted(period) : labelForReps(period))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 2)

                if let msg = vm.emptyMessage, vm.points.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text(msg).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let rawDaily: [(Date, Double)] = vm.points.map { p in
                        (startOfDay(p.date), displayValue(p.valueKgOrReps))
                    }

                    let now = Date()
                    let cal = Calendar.current
                    let startThisYear = startOfYear(now)

                    let series: [(Date, Double)] = {
                        switch period {
                        case .ytd:
                            let filtered = rawDaily.filter { $0.0 >= startThisYear && $0.0 <= now }
                            return aggregateMax(by: .day, points: filtered, calendar: cal)
                        case .monthly:
                            let filtered = rawDaily.filter { $0.0 >= startThisYear && $0.0 <= now }
                            return aggregateMax(by: .month, points: filtered, calendar: cal)
                        case .yearly:
                            let filtered = rawDaily.filter {
                                cal.component(.year, from: $0.0) <= cal.component(.year, from: now)
                            }
                            return aggregateMax(by: .year, points: filtered, calendar: cal)
                        }
                    }()

                    Chart {
                        ForEach(series.indices, id: \.self) { i in
                            let p = series[i]
                            LineMark(
                                x: .value("Date", p.0),
                                y: .value(vm.isWeighted ? (usePounds ? "lb" : "kg") : "reps", p.1)
                            )
                            PointMark(
                                x: .value("Date", p.0),
                                y: .value(vm.isWeighted ? (usePounds ? "lb" : "kg") : "reps", p.1)
                            )
                            // Mostrar siempre si hay 1 punto; si no, solo al seleccionar
                            .opacity(series.count <= 1 ? 1 : (selPoint?.date == p.0 ? 1 : 0))
                            .symbolSize(60)
                        }
                    }
                    .chartXAxis {
                        switch period {
                        case .ytd:     AxisMarks(values: .automatic(desiredCount: 6))
                        case .monthly: AxisMarks(values: .stride(by: .month))
                        case .yearly:  AxisMarks(values: .stride(by: .year))
                        }
                    }
                    .chartYAxis { AxisMarks() }
                    .contentShape(Rectangle())
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            let plot = geo[proxy.plotAreaFrame]
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                    let xInPlot = value.location.x - plot.minX
                                    if let d: Date = proxy.value(atX: xInPlot) {
                                        let target = d.timeIntervalSince1970
                                        let xs = series.map { $0.0.timeIntervalSince1970 }
                                        if let idx = nearestIndex(target, in: xs) {
                                            let p = series[idx]; selPoint = (date: p.0, value: p.1)
                                        }
                                    }
                                })

                            // ——— Callout + guía vertical (como View, no RuleMark) ———
                            if let s = selPoint,
                               let px = proxy.position(forX: s.date),
                               let py = proxy.position(forY: s.value) {

                                // guía vertical
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.35))
                                    .frame(width: 1, height: plot.size.height)
                                    .position(x: plot.origin.x + px, y: plot.midY)

                                let margin: CGFloat = 40
                                let plotRect = geo[proxy.plotAreaFrame]
                                let clampedX = min(max(plot.origin.x + px, plotRect.minX + margin), plotRect.maxX - margin)
                                let clampedY = min(max(plot.origin.y + py - 28, plotRect.minY + margin/2), plotRect.maxY - margin/2)
                                let title = vm.isWeighted ? displayWeight(s.value) : String(format: "%.0f reps", s.value)
                                let subtitle = SummaryView.formatDate(s.date)
                                LocalCallout(title: title, subtitle: subtitle)
                                    .position(x: clampedX, y: clampedY)
                            }
                        }
                    }
                    .frame(height: 260)

                    if let last = series.last {
                        let lastStr = vm.isWeighted ? displayWeight(last.1) : String(format: "%.0f reps", last.1)
                        let bestVal = series.map { $0.1 }.max() ?? last.1
                        let bestStr = vm.isWeighted ? displayWeight(bestVal) : String(format: "%.0f reps", bestVal)
                        Text("Last: \(lastStr) • Best: \(bestStr)")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.load(period: period); selPoint = nil }
            .onChange(of: period) { _ in vm.load(period: period); selPoint = nil }
        }
    }

    // MARK: - Labels / Aggregation helpers
    private func labelForWeighted(_ p: Period) -> String {
        switch p {
        case .ytd:     return "Max weight per day (YTD)"
        case .monthly: return "Max weight per month"
        case .yearly:  return "Max weight per year"
        }
    }
    private func labelForReps(_ p: Period) -> String {
        switch p {
        case .ytd:     return "Max reps per day (YTD)"
        case .monthly: return "Max reps per month"
        case .yearly:  return "Max reps per year"
        }
    }

    private enum Bucket { case day, month, year }

    private func aggregateMax(by bucket: Bucket, points: [(Date, Double)], calendar cal: Calendar) -> [(Date, Double)] {
        var dict: [Date: Double] = [:]
        for (d, v) in points {
            let key: Date
            switch bucket {
            case .day:
                key = startOfDay(d)
            case .month:
                key = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
            case .year:
                key = cal.date(from: DateComponents(year: cal.component(.year, from: d))) ?? d
            }
            dict[key] = max(dict[key] ?? 0, v)
        }
        return dict.keys.sorted().map { ($0, dict[$0] ?? 0) }
    }

    private func startOfDay(_ d: Date) -> Date { Calendar.current.startOfDay(for: d) }
    private func startOfYear(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: DateComponents(year: cal.component(.year, from: d))) ?? d
    }

    private func displayWeight(_ kg: Double) -> String {
        let val = usePounds ? UnitFormatters.kgToLb(kg) : kg
        let unit = usePounds ? "lb" : "kg"
        let fmt = usePounds ? "%.0f %@" : "%.1f %@"
        return String(format: fmt, val, unit)
    }
    private func displayValue(_ v: Double) -> Double {
        vm.isWeighted ? (usePounds ? UnitFormatters.kgToLb(v) : v) : v
    }
    private func nearestIndex(_ x: Double, in xs: [Double]) -> Int? {
        guard !xs.isEmpty else { return nil }
        var best = 0; var bestDist = abs(xs[0] - x)
        for i in 1..<xs.count {
            let d = abs(xs[i] - x)
            if d < bestDist { best = i; bestDist = d }
        }
        return best
    }
}
