import SwiftUI
import Charts
import SwiftData   // <- para consultar RunningSession al seleccionar un punto

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

// MARK: - Callout reutilizable

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

                // Teaser: últimos puntos
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
    @Environment(\.modelContext) private var context   // <- acceso a SwiftData

    let bucket: RecordBucket
    let prefersMiles: Bool
    let points: [PacePoint]

    @State private var scope: ChartScope = .ytd
    @State private var selectedPoint: PacePoint? = nil
    @State private var selectedRun: RunningSession? = nil   // <- sesión mapeada al punto

    private var unitLabel: String { prefersMiles ? "min/mi" : "min/km" }

    // ---- Serie según el tab seleccionado ----
    private var series: [PacePoint] {
        switch scope {
        case .ytd:
            return ytdDailyBest(points: points)                  // mejor por día, año actual
        case .monthly:
            return monthlyBestCurrentYear(points: points)        // mejor por mes, año actual
        case .yearly:
            return yearlyBest(points: points)                    // mejor por año, todos los años
        }
    }

    private var best: Double { series.map(\.paceSecPerUnit).min() ?? .infinity }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $scope) {
                    ForEach(ChartScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(titleForBucket()).font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
                Text(labelForPeriod()).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

                let s = series
                Chart {
                    ForEach(s.indices, id: \.self) { i in
                        let p = s[i]
                        LineMark(x: .value("Date", p.date),
                                 y: .value(axisTitle(), -p.paceSecPerUnit))
                        PointMark(x: .value("Date", p.date),
                                  y: .value(axisTitle(), -p.paceSecPerUnit))
                        .opacity(s.count <= 1 ? 1 : (selectedPoint?.date == p.date ? 1 : 0))
                        .symbolSize(60)
                    }
                }
                .chartXAxis {
                    switch scope {
                    case .ytd:     AxisMarks(values: .automatic(desiredCount: 6))
                    case .monthly: AxisMarks(values: .stride(by: .month))
                    case .yearly:  AxisMarks(values: .stride(by: .year))
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .extended) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let y = v.as(Double.self) { Text(paceString(-y)) } }
                    }
                }
                .contentShape(Rectangle())
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plot = geo[proxy.plotAreaFrame]
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                let xInPlot = value.location.x - plot.minX
                                if let d: Date = proxy.value(atX: xInPlot) {
                                    let xs = s.map { $0.date.timeIntervalSince1970 }
                                    if let idx = nearestIndex(d.timeIntervalSince1970, in: xs) {
                                        let p = s[idx]
                                        selectedPoint = p
                                        // Mapear el punto agregado a una sesión real del periodo
                                        selectedRun = findRun(for: p, scope: scope, bucket: bucket, prefersMiles: prefersMiles)
                                    }
                                }
                            })
                        if let sel = selectedPoint,
                           let px = proxy.position(forX: sel.date),
                           let py = proxy.position(forY: -sel.paceSecPerUnit) {
                            // Guía vertical como View
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 1, height: plot.size.height)
                                .position(x: plot.origin.x + px, y: plot.midY)

                            let margin: CGFloat = 40
                            let clampedX = min(max(plot.origin.x + px, plot.minX + margin), plot.maxX - margin)
                            let clampedY = min(max(plot.origin.y + py - 28, plot.minY + margin/2), plot.maxY - margin/2)
                            ChartCallout(title: "\(paceString(sel.paceSecPerUnit)) \(unitLabel)",
                                         subtitle: labelForX(sel.date))
                            .position(x: clampedX, y: clampedY)
                        }
                    }
                }
                // Más compacto: ~38% de la pantalla; mínimo 200 pt
                .frame(height: (vSize == .compact) ? nil : max(200, UIScreen.main.bounds.height * 0.38))
                .frame(maxHeight: (vSize == .compact) ? .infinity : nil, alignment: .top)

                // --- Acceso al detalle del running seleccionado ---
                if let run = selectedRun {
                    NavigationLink {
                        RunningSessionDetail(session: run)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "figure.run")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open run details")
                                    .font(.headline)
                                Text(labelForX(run.date))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }

                if let last = s.last {
                    let bestVal = s.map(\.paceSecPerUnit).min() ?? last.paceSecPerUnit
                    Text("Last: \(paceString(last.paceSecPerUnit)) • Best: \(paceString(bestVal))")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("\(bucket.display) pace")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .onChange(of: scope) { _ in
                selectedPoint = nil
                selectedRun = nil
            }
        }
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
        case .ytd:     return SummaryView.formatDate(date) // formateador ya existente
        case .monthly: return monthYearFormatter.string(from: date)
        case .yearly:  return yearFormatter.string(from: date)
        }
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

    // ---- Agregaciones pedidas ----

    /// YTD: desde el 1 de enero del año actual hasta hoy, mejor pace por DÍA.
    private func ytdDailyBest(points: [PacePoint]) -> [PacePoint] {
        let cal = Calendar.current
        let now = Date()
        let startOfYear = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!
        var bestByDay: [Date: Double] = [:]
        for p in points where p.date >= startOfYear && p.date <= now {
            let day = cal.startOfDay(for: p.date)
            bestByDay[day] = min(bestByDay[day] ?? .infinity, p.paceSecPerUnit)
        }
        return bestByDay.keys.sorted().map { d in
            PacePoint(date: d, paceSecPerUnit: bestByDay[d] ?? .infinity)
        }
    }

    /// Monthly: año actual hasta hoy, mejor pace por MES.
    /// Usamos la fecha anclada al primer día del mes como clave para evitar
    /// problemas de igualdad con DateComponents.
    private func monthlyBestCurrentYear(points: [PacePoint]) -> [PacePoint] {
        let cal = Calendar.current
        let now = Date()
        let startOfYear = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!

        // clave = inicio de mes (Date), valor = mejor pace de ese mes
        var bestByMonth: [Date: Double] = [:]
        for p in points where p.date >= startOfYear && p.date <= now {
            let comps = cal.dateComponents([.year, .month], from: p.date)
            if let monthStart = cal.date(from: comps) {
                bestByMonth[monthStart] = min(bestByMonth[monthStart] ?? .infinity, p.paceSecPerUnit)
            }
        }

        // Recorremos enero..mes actual e incluimos los meses con datos
        var result: [PacePoint] = []
        for m in monthAnchors(from: startOfYear, to: now, calendar: cal) {
            if let v = bestByMonth[m] {
                result.append(PacePoint(date: m, paceSecPerUnit: v))
            }
        }
        return result
    }

    /// Genera anclas al primer día de cada mes entre start y end (inclusive).
    private func monthAnchors(from start: Date, to end: Date, calendar cal: Calendar) -> [Date] {
        var out: [Date] = []
        var d = start
        while d <= end {
            if let anchor = cal.date(from: cal.dateComponents([.year, .month], from: d)) {
                out.append(anchor)
            }
            d = cal.date(byAdding: .month, value: 1, to: d)!
        }
        return out
    }

    /// Yearly: mejor pace por AÑO para todos los años con datos.
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

    // Etiquetas y títulos

    private func titleForBucket() -> String { "\(bucket.display)" }
    private func labelForPeriod() -> String {
        switch scope {
        case .ytd:     return "Best pace per day (YTD)"
        case .monthly: return "Best pace per month"
        case .yearly:  return "Best pace per year"
        }
    }
    private func axisTitle() -> String { prefersMiles ? "min/mi (plot)" : "min/km (plot)" }

    // MARK: - Buscar la sesión (SwiftData) que corresponde al punto seleccionado

    private func findRun(for point: PacePoint,
                         scope: ChartScope,
                         bucket: RecordBucket,
                         prefersMiles: Bool) -> RunningSession? {
        // Rango de fechas del periodo del punto seleccionado
        let cal = Calendar.current
        let start: Date
        let end: Date
        switch scope {
        case .ytd:
            start = cal.startOfDay(for: point.date)
            end   = cal.date(byAdding: .day, value: 1, to: start)!
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: point.date)
            start = cal.date(from: comps)!
            end   = cal.date(byAdding: .month, value: 1, to: start)!
        case .yearly:
            let y = cal.component(.year, from: point.date)
            start = cal.date(from: DateComponents(year: y, month: 1, day: 1))!
            end   = cal.date(byAdding: .year, value: 1, to: start)!
        }

        // Fetch de las sesiones del periodo y bucket (>= distancia objetivo)
        let minMeters = bucket.km * 1000.0
        let pred = #Predicate<RunningSession> {
            $0.date >= start && $0.date < end && $0.distanceMeters >= minMeters
        }
        let desc = FetchDescriptor<RunningSession>(
            predicate: pred,
            sortBy: [SortDescriptor(\RunningSession.date, order: .forward)]
        )
        let runs = (try? context.fetch(desc)) ?? []
        guard !runs.isEmpty else { return nil }

        // Elige el que tenga pace más cercano (o idéntico) al punto agregado
        func paceSecPerUnit(_ r: RunningSession) -> Double {
            let km = max(r.distanceMeters / 1000.0, 0.001)
            let secPerKm = Double(r.durationSeconds) / km
            return prefersMiles ? secPerKm * 1.609344 : secPerKm
        }
        let target = point.paceSecPerUnit
        return runs.min(by: { abs(paceSecPerUnit($0) - target) < abs(paceSecPerUnit($1) - target) })
    }
}

