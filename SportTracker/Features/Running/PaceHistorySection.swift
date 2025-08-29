import SwiftUI
import Charts

// MARK: - Tipos

enum RecordBucket: CaseIterable, Comparable {
    case k1, k3, k5, k10, half, marathon
    var km: Double {
        switch self {
        case .k1: return 1
        case .k3: return 3
        case .k5: return 5
        case .k10: return 10
        case .half: return 21.0975
        case .marathon: return 42.195
        }
    }
    var display: String {
        switch self {
        case .k1: return "1K"
        case .k3: return "3K"
        case .k5: return "5K"
        case .k10: return "10K"
        case .half: return "Half"
        case .marathon: return "Marathon"
        }
    }
    static func < (lhs: RecordBucket, rhs: RecordBucket) -> Bool { lhs.km < rhs.km }
}

func bucket(for distanceKm: Double) -> RecordBucket? {
    RecordBucket.allCases.filter { $0.km <= distanceKm }.max()
}

struct PacePoint: Identifiable {
    var id: Date { date }
    let date: Date
    let paceSecPerUnit: Double
}

// MARK: - Helpers

@inline(__always)
func paceString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%d:%02d", m, s)
}

@inline(__always)
func pacePerUnit(seconds: Double, distanceKm: Double, prefersMiles: Bool) -> Double {
    guard distanceKm > 0 else { return .infinity }
    let secPerKm = seconds / distanceKm
    return prefersMiles ? secPerKm * 1.609344 : secPerKm
}

// MARK: - Callout reutilizable (más claro)

private struct ChartCallout: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Vista compacta (abre Insights)

struct PaceHistorySection: View {
    let bucket: RecordBucket
    let prefersMiles: Bool
    let points: [PacePoint]

    @State private var showFull = false

    var body: some View {
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pace trend • \(bucket.display)")
                    .font(.headline)

                // Pequeño teaser: últimos puntos
                Chart {
                    ForEach(points.suffix(min(points.count, 20))) { p in
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value("PacePlot", -p.paceSecPerUnit)
                        )
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Date", p.date),
                            y: .value("PacePlot", -p.paceSecPerUnit)
                        )
                        .symbolSize(20)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(paceString(-v))
                            }
                        }
                    }
                }
                .frame(height: 180)
                .onTapGesture { showFull = true }

                Button {
                    showFull = true
                } label: {
                    Label("Insights", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $showFull) {
                FullScreenPaceChart(bucket: bucket,
                                    prefersMiles: prefersMiles,
                                    points: points)
            }
        }
    }
}

// MARK: - Pantalla completa con tabs

private enum ChartScope: String, CaseIterable, Identifiable {
    case ytd = "YTD"
    case monthly = "Monthly"
    case yearly = "Yearly"
    var id: String { rawValue }
}

struct FullScreenPaceChart: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vSize
    let bucket: RecordBucket
    let prefersMiles: Bool
    let points: [PacePoint]

    @State private var scope: ChartScope = .ytd
    @State private var selectedPoint: PacePoint? = nil

    private var unitLabel: String { prefersMiles ? "min/mi" : "min/km" }

    // Serie según el tab seleccionado
    private var series: [PacePoint] {
        switch scope {
        case .ytd:
            let y = Calendar.current.component(.year, from: Date())
            return points.filter { Calendar.current.component(.year, from: $0.date) == y }
                         .sorted { $0.date < $1.date }
        case .monthly:
            return monthlyBest(points: points, lastMonths: 12)
        case .yearly:
            return yearlyBest(points: points)
        }
    }

    private var best: Double { series.map(\.paceSecPerUnit).min() ?? .infinity }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Scope", selection: $scope) {
                    ForEach(ChartScope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if series.isEmpty {
                    ContentUnavailableView(
                        "No data",
                        systemImage: "chart.xyaxis.line",
                        description: Text("No hay registros para \(scope.rawValue.lowercased()).")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Chart {
                        ForEach(series) { p in
                            LineMark(
                                x: .value("Date", p.date),
                                y: .value("PacePlot", -p.paceSecPerUnit)
                            )
                            .interpolationMethod(.monotone)

                            PointMark(
                                x: .value("Date", p.date),
                                y: .value("PacePlot", -p.paceSecPerUnit)
                            )
                            .symbolSize(28)
                        }

                        if best.isFinite {
                            RuleMark(y: .value("BestPlot", -best))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .leading) {
                                    Text("Best: \(paceString(best)) \(unitLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(paceString(-v))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        if scope == .yearly {
                            AxisMarks(values: .stride(by: .year)) { v in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let d = v.as(Date.self) {
                                        Text(yearFormatter.string(from: d))
                                    }
                                }
                            }
                        } else {
                            AxisMarks(values: .stride(by: .month)) { v in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let d = v.as(Date.self) {
                                        Text(monthShortFormatter.string(from: d))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    // Overlay: gesto + callout dibujado dentro del plot y "clamp" a los bordes
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            let plot = geo[proxy.plotAreaFrame]

                            // Gesto de selección
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let locationX = value.location.x - plot.origin.x
                                            if let date: Date = proxy.value(atX: locationX),
                                               let nearest = nearestPoint(to: date, in: series) {
                                                selectedPoint = nearest
                                            }
                                        }
                                )

                            // Callout de la selección (si hay)
                            if let sel = selectedPoint,
                               let x = proxy.position(forX: sel.date),
                               let y = proxy.position(forY: -sel.paceSecPerUnit) {

                                // Posición absoluta dentro del GeometryReader
                                let px = plot.origin.x + x
                                let py = plot.origin.y + y

                                // Márgenes para que no se salga
                                let margin: CGFloat = 40
                                let clampedX = min(max(px, plot.minX + margin), plot.maxX - margin)
                                // Sitúalo un poco por encima del punto, pero sin rebasar tabs ni borde superior
                                let desiredY = py - 28
                                let clampedY = min(max(desiredY, plot.minY + margin/2), plot.maxY - margin/2)

                                ChartCallout(
                                    title: "\(paceString(sel.paceSecPerUnit)) \(unitLabel)",
                                    subtitle: labelForX(sel.date)
                                )
                                .position(x: clampedX, y: clampedY)
                            }
                        }
                    }
                    // Altura: en portrait (sizeClass vertical = .regular) ocupa ~la mitad de la pantalla.
                    // En landscape (sizeClass vertical = .compact) lo dejamos como está (llenando).
                    .frame(height: (vSize == .compact) ? nil : max(240, UIScreen.main.bounds.height * 0.5))
                    .frame(maxHeight: (vSize == .compact) ? .infinity : nil, alignment: .top)

                }
            }
            .navigationTitle("\(bucket.display) pace")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            // IMPORTANTE: NO ignoramos safe area => las etiquetas del eje Y no quedan bajo la isla
            .frame(
                maxWidth: .infinity,
                maxHeight: (vSize == .compact) ? nil : .infinity,
                alignment: .top
            )
            .brandHeaderSpacer()
        }
        // Rotación habilitada en Insights (requiere OrientationSupport.swift)
        .onAppear { OrientationLockDelegate.allowPortraitAndLandscape() }
        .onDisappear { OrientationLockDelegate.lockPortrait() }
        .onChange(of: scope) { _ in selectedPoint = nil }
    }

    // MARK: - Formatters & helpers

    private var monthShortFormatter: DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }
    private var monthYearFormatter: DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return f
    }
    private var yearFormatter: DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yyyy")
        return f
    }

    private func labelForX(_ date: Date) -> String {
        switch scope {
        case .ytd:     return SummaryView.formatDate(date)
        case .monthly: return monthYearFormatter.string(from: date)
        case .yearly:  return yearFormatter.string(from: date)
        }
    }

    private func nearestPoint(to date: Date, in series: [PacePoint]) -> PacePoint? {
        guard !series.isEmpty else { return nil }
        return series.min { a, b in
            abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
        }
    }

    /// Últimos `lastMonths` meses (incluido el actual), mejor registro por mes (solo meses con datos).
    private func monthlyBest(points: [PacePoint], lastMonths: Int) -> [PacePoint] {
        let cal = Calendar.current
        guard let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return [] }
        guard let start = cal.date(byAdding: .month, value: -(lastMonths - 1), to: startMonth) else { return [] }

        var bestByMonth: [DateComponents: Double] = [:]
        for p in points where p.date >= start {
            let comps = cal.dateComponents([.year, .month], from: p.date)
            let key = DateComponents(year: comps.year, month: comps.month)
            bestByMonth[key] = min(bestByMonth[key] ?? .infinity, p.paceSecPerUnit)
        }

        var result: [PacePoint] = []
        var d = start
        let end = Date()
        while d <= end {
            let comps = cal.dateComponents([.year, .month], from: d)
            if let value = bestByMonth[comps], let anchor = cal.date(from: comps) {
                result.append(PacePoint(date: anchor, paceSecPerUnit: value))
            }
            d = cal.date(byAdding: .month, value: 1, to: d)!
        }
        return result
    }

    /// Mejor registro por año (para todos los años disponibles).
    private func yearlyBest(points: [PacePoint]) -> [PacePoint] {
        let cal = Calendar.current
        var bestByYear: [Int: Double] = [:]
        for p in points {
            let y = cal.component(.year, from: p.date)
            bestByYear[y] = min(bestByYear[y] ?? .infinity, p.paceSecPerUnit)
        }
        let years = bestByYear.keys.sorted()
        return years.compactMap { y in
            guard let val = bestByYear[y],
                  let d = cal.date(from: DateComponents(year: y, month: 1, day: 1)) else { return nil }
            return PacePoint(date: d, paceSecPerUnit: val)
        }
    }
    
}
