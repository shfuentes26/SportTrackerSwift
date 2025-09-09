import SwiftUI
import SwiftData
import Charts

private enum TimeWindow: String, CaseIterable, Identifiable {
    case m1 = "1M"
    case m12 = "12M"
    case all = "All"

    var id: String { rawValue }
    var months: Int? {
        switch self {
        case .m1:  return 1
        case .m12: return 12
        case .all: return nil
        }
    }
}

struct MeasurementHistoryView: View {
    @Environment(\.modelContext) private var context

    let kind: MeasurementKind

    @Query private var settingsList: [Settings]
    private var prefersPounds: Bool { settingsList.first?.prefersPounds ?? false }
    private var prefersInches: Bool { false }

    // Descendente (más recientes primero) para la lista
    @Query(sort: [SortDescriptor(\BodyMeasurement.date, order: .reverse)])
    private var allDesc: [BodyMeasurement]

    // UI
    @State private var showAdd = false
    @State private var window: TimeWindow = .m12

    // Series for the chart (computed off the main thread)
    @State private var series: [(Date, Double)] = []
    @State private var isLoading = false

    init(kind: MeasurementKind) {
        self.kind = kind
        let pred: Predicate<BodyMeasurement> = #Predicate { $0.kindRaw == kind.rawValue }
        _allDesc = Query(filter: pred,
                         sort: [SortDescriptor(\BodyMeasurement.date, order: .reverse)])
    }

    // MARK: - Derived

    private var startDateForWindow: Date? {
        guard let months = window.months else { return nil }
        return Calendar.current.date(byAdding: .month, value: -months, to: Date())
    }

    private var entries: [BodyMeasurement] {
        if let start = startDateForWindow {
            return allDesc.filter { $0.date >= start }
        } else {
            return allDesc
        }
    }

    private var xDomain: ClosedRange<Date>? {
        guard let start = startDateForWindow else { return nil }
        return start...Date()
    }

    // Dynamic Y range (padding ~10%)
    private var yDomain: ClosedRange<Double> {
        let ys = entries.map { yValue($0) }
        let minV = ys.min() ?? 0
        let maxV = ys.max() ?? 1
        if minV == maxV { return (minV - 1)...(maxV + 1) }
        let span = maxV - minV
        let pad  = max(0.5, span * 0.1)
        return (minV - pad)...(maxV + pad)
    }

    private var showPointMarks: Bool {
        series.count <= smoothingThreshold(for: window)
    }

    // MARK: - Body

    var body: some View {
        List {
            if !entries.isEmpty {
                Section {
                    Picker("Range", selection: $window) {
                        ForEach(TimeWindow.allCases) { w in
                            Text(w.rawValue).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Trend") {
                    ZStack {
                        // Chart
                        if let domainX = xDomain {
                            Chart(series, id: \.0) { (date, value) in
                                LineMark(x: .value("Date", date), y: .value("Value", value))
                                if showPointMarks {
                                    PointMark(x: .value("Date", date), y: .value("Value", value))
                                }
                            }
                            .frame(height: 220)
                            .chartYAxisLabel(kind.isLength ? (prefersInches ? "in" : "cm")
                                                          : (prefersPounds ? "lb" : "kg"))
                            .chartXScale(domain: domainX)
                            .chartYScale(domain: yDomain)
                        } else {
                            Chart(series, id: \.0) { (date, value) in
                                LineMark(x: .value("Date", date), y: .value("Value", value))
                                if showPointMarks {
                                    PointMark(x: .value("Date", date), y: .value("Value", value))
                                }
                            }
                            .frame(height: 220)
                            .chartYAxisLabel(kind.isLength ? (prefersInches ? "in" : "cm")
                                                          : (prefersPounds ? "lb" : "kg"))
                            .chartYScale(domain: yDomain)
                        }

                        // Spinner while building the series
                        if isLoading {
                            ProgressView()
                                .controlSize(.large)
                                .padding()
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }

            Section("Entries") {
                ForEach(entries) { m in
                    HStack {
                        Text(m.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(display(m)).foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(kind.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddMeasurementView(initialKind: kind)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // Build the chart series off the main thread
        .task { await rebuildSeries() }
        .onChange(of: window) { _ in Task { await rebuildSeries() } }
        .onChange(of: allDesc) { _ in Task { await rebuildSeries() } }
    }

    // MARK: - Build series (async)

    private func yValue(_ m: BodyMeasurement) -> Double {
        if kind.isLength {
            return prefersInches ? (m.value / 2.54) : m.value
        } else {
            return prefersPounds ? (m.value * 2.20462) : m.value
        }
    }

    @MainActor
    private func setLoading(_ loading: Bool) { isLoading = loading }

    private func rebuildSeries() async {
        await setLoading(true)

        // Snapshot en main
        let snapshot = entries.map { ($0.date, yValue($0)) }

        // Trabajo pesado fuera del main
        let computed: [(Date, Double)] = await withTaskGroup(of: [(Date, Double)].self,
                                                             returning: [(Date, Double)].self) { _ in
            // sort + downsample + suavizado condicional por ventana
            let base = snapshot.sorted { $0.0 < $1.0 }
            var pts  = downsample(points: base, maxPoints: maxChartPoints(for: window))

            let threshold = smoothingThreshold(for: window)
            if pts.count > threshold {
                // ventana de media móvil dinámica (3...12)
                let w = max(3, min(12, pts.count / 50))
                pts = movingAverage(pts, window: w)
            }
            return pts
        }

        await MainActor.run {
            self.series = computed
            self.isLoading = false
        }
    }


    // MARK: - Helpers

    private func display(_ m: BodyMeasurement) -> String {
        if kind.isLength {
            return MeasurementFormatters.formatLength(cm: m.value, prefersInches: prefersInches)
        } else {
            return MeasurementFormatters.formatWeight(kg: m.value, prefersPounds: prefersPounds)
        }
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(entries[idx])
        }
        try? context.save()
        Task { await rebuildSeries() }
    }

    /// Reduce the number of points so the chart stays snappy.
    private func downsample(points: [(Date, Double)], maxPoints: Int) -> [(Date, Double)] {
        guard points.count > maxPoints, maxPoints > 0 else { return points }
        let step = max(1, points.count / maxPoints)
        var sampled: [(Date, Double)] = []
        sampled.reserveCapacity(min(maxPoints, points.count))

        var i = 0
        while i < points.count {
            sampled.append(points[i])
            i += step
        }
        if let last = points.last, sampled.last?.0 != last.0 { sampled.append(last) }
        return sampled
    }

    /// Simple moving average; uses each point's date.
    private func movingAverage(_ pts: [(Date, Double)], window: Int) -> [(Date, Double)] {
        guard window > 1, pts.count > window else { return pts }
        var result: [(Date, Double)] = []
        result.reserveCapacity(pts.count)

        for i in pts.indices {
            let start = max(0, i - (window - 1))
            let end   = i
            let slice = pts[start...end]
            let avg   = slice.reduce(0.0) { $0 + $1.1 } / Double(slice.count)
            result.append((pts[i].0, avg))
        }
        return result
    }
    
    // Umbral de suavizado por ventana (puedes ajustarlos)
    private func smoothingThreshold(for window: TimeWindow) -> Int {
        switch window {
        case .m1:  return .max      // nunca suavizamos 1M
        case .m12: return 50       // suaviza si >160 puntos
        case .all: return 180       // suaviza si >180 puntos
        }
    }

    // (opcional) límite de puntos tras downsample
    private func maxChartPoints(for window: TimeWindow) -> Int {
        switch window {
        case .m1:  return 31
        case .m12: return 50
        case .all: return 300
        }
    }

}
