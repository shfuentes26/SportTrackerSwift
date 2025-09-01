// TrainingDetailView.swift
import SwiftUI
import MapKit
import CoreLocation
import SwiftData
import Charts

typealias RunMetrics = HealthKitImportService.RunMetrics

enum TrainingItem {
    case running(RunningSession)
    case gym(StrengthSession)
}

struct TrainingDetailView: View {
    let item: TrainingItem

    var body: some View {
        switch item {
        case .running(let s):
            RunningSessionDetail(session: s)
        case .gym(let s):
            GymSessionDetail(session: s)
        }
    }
}

// MARK: - Running detail

struct RunningSessionDetail: View {
    let session: RunningSession
    @State private var region = MKCoordinateRegion()

    // Datos
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [Settings]
    private var useMiles: Bool { settingsList.first?.prefersMiles ?? false }

    // --- Insights full screen ---
    @State private var insights: InsightsPayload? = nil
    private struct InsightsPayload: Identifiable {
        let id = UUID()
        let bucket: RecordBucket
        let points: [PacePoint]
    }
    
    @State private var metrics: RunMetrics? = nil
    @State private var selectedIndex: Int = 0  // índice dentro de las pestañas disponibles
    
    // Selecciones para mostrar el callout
    @State private var selPace: (t: TimeInterval, v: Double)? = nil
    @State private var selElev: (t: TimeInterval, v: Double)? = nil
    @State private var selHR:   (t: TimeInterval, v: Double)? = nil

    // Callout simple reutilizable (similar al de Insights)
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
    
    /// Convierte un TimeInterval en "hh:mm:ss"
    private func timeLabel(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // Índice más cercano por eje X
    private func nearestIndex(_ x: Double, in xs: [Double]) -> Int? {
        guard !xs.isEmpty else { return nil }
        var best = 0; var bestDist = abs(xs[0] - x)
        for i in 1..<xs.count {
            let d = abs(xs[i] - x)
            if d < bestDist { best = i; bestDist = d }
        }
        return best
    }

    private enum AnalysisTab: Int, CaseIterable {
        case pace, elevation, hr
        var title: String { self == .pace ? "Pace" : (self == .elevation ? "Elevation" : "HR") }
    }

    private func availableTabs(for m: RunMetrics) -> [AnalysisTab] {
        var tabs: [AnalysisTab] = []
        if !m.paceSeries.isEmpty      { tabs.append(.pace) }
        if !m.elevationSeries.isEmpty { tabs.append(.elevation) }
        if !m.heartRateSeries.isEmpty { tabs.append(.hr) }
        return tabs
    }

    private var routeCoords: [CLLocationCoordinate2D]? {
        guard let poly = session.routePolyline, !poly.isEmpty else { return nil }
        return Polyline.decode(poly)
    }
    
    var body: some View {
        ScrollView {
            if let coords = routeCoords {
                RouteMapView(coords: coords)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            } else {
                Map(coordinateRegion: $region)
                    .onAppear { region = defaultRegion() }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            }
            VStack(spacing: 20) {
                Metric(value: formatDistance(session.distanceMeters), label: "Distance")
                Metric(value: formatElapsed(session.durationSeconds), label: "Time")
                Metric(
                    value: formatPace(distanceMeters: session.distanceMeters, durationSeconds: session.durationSeconds),
                    label: "Pace"
                )

                Text("\(Int(session.totalPoints)) pts • \(SummaryView.formatDate(session.date))")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if let notes = session.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(.headline)
                        Text(notes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                analysisSection

                // ---- Botón "Insights" (pill) ----
                if let b = bucket(for: session.distanceMeters / 1000.0) {
                    let pts = fetchPaceHistory(for: b, prefersMiles: useMiles)
                    if pts.count >= 2 {
                        Button {
                            insights = .init(bucket: b, points: pts)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "chart.xyaxis.line")
                                Text("Insights").font(.headline)
                            }
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .systemBlue).opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .navigationTitle("Running")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $insights) { payload in
            FullScreenPaceChart(bucket: payload.bucket,
                                prefersMiles: useMiles,
                                points: payload.points)
        }
        .task {
            metrics = try? await HealthKitImportService.fetchRunMetrics(for: session)
            selectedIndex = 0
        }
    }

    private func fetchPaceHistory(for bucket: RecordBucket, prefersMiles: Bool) -> [PacePoint] {
        let minMeters = bucket.km * 1000.0
        let pred = #Predicate<RunningSession> { $0.distanceMeters >= minMeters }
        var desc = FetchDescriptor<RunningSession>(
            predicate: pred,
            sortBy: [SortDescriptor(\RunningSession.date, order: .forward)]
        )
        let runs = (try? context.fetch(desc)) ?? []

        return runs.map { r in
            let km = max(r.distanceMeters / 1000.0, 0.001)
            let pace = pacePerUnit(seconds: Double(r.durationSeconds),
                                   distanceKm: km,
                                   prefersMiles: prefersMiles)
            return PacePoint(date: r.date, paceSecPerUnit: pace)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f km", km)
    }
    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds/3600, m = (seconds%3600)/60, s = Int(seconds%60)
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    private func formatPace(distanceMeters: Double, durationSeconds: Int) -> String {
        let km = max(distanceMeters / 1000.0, 0.001)
        let secPerKm = Double(durationSeconds) / km
        let secPerUnit = useMiles ? secPerKm * 1.609344 : secPerKm
        let m = Int(secPerUnit) / 60
        let s = Int(secPerUnit) % 60
        let unit = useMiles ? "min/mi" : "min/km"
        return String(format: "%d:%02d %@", m, s, unit)
    }
    
    private func paceLabel(_ secondsPerUnit: Double) -> String {
        let m = Int(secondsPerUnit) / 60
        let s = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d", m, s)
    }
    
    @ViewBuilder
    private var analysisSection: some View {
        if let m = metrics {
            let tabs = availableTabs(for: m)
            if !tabs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Analysis").font(.headline)

                    let safeIndex = min(selectedIndex, max(tabs.count - 1, 0))

                    Picker("", selection: Binding(
                        get: { safeIndex },
                        set: { newVal in selectedIndex = newVal }
                    )) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                            Text(tab.title).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: tabs) { _ in selectedIndex = 0 }

                    Group {
                        switch tabs[safeIndex] {
                        case .pace:
                            let series = m.paceSeries.map { p -> (Double, Double) in
                                let val = useMiles ? p.secPerKm * 1.609344 : p.secPerKm
                                return (p.time, val)
                            }
                            Chart {
                                ForEach(series.indices, id: \.self) { i in
                                    let p = series[i]
                                    LineMark(x: .value("t", p.0),
                                             y: .value(useMiles ? "sec/mi" : "sec/km", p.1))
                                    PointMark(x: .value("t", p.0),
                                              y: .value(useMiles ? "sec/mi" : "sec/km", p.1))
                                        .opacity(selPace?.t == p.0 ? 1 : 0)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(preset: .extended) { v in
                                    AxisGridLine(); AxisTick()
                                    AxisValueLabel {
                                        if let y = v.as(Double.self) {
                                            Text(paceLabel(y))
                                        }
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    let plot = geo[proxy.plotAreaFrame]
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0).onChanged { value in
                                                let xInPlot = value.location.x - plot.minX
                                                if let xVal: Double = proxy.value(atX: xInPlot) {
                                                    let xs = series.map { $0.0 }
                                                    if let idx = nearestIndex(xVal, in: xs) {
                                                        let p = series[idx]
                                                        selPace = (p.0, p.1)
                                                    }
                                                }
                                            }
                                        )
                                    if let s = selPace,
                                       let px = proxy.position(forX: s.t),
                                       let py = proxy.position(forY: s.v) {
                                        let margin: CGFloat = 40
                                        let clampedX = min(max(plot.origin.x + px, plot.minX + margin), plot.maxX - margin)
                                        let clampedY = min(max(plot.origin.y + py - 28, plot.minY + margin/2), plot.maxY - margin/2)
                                        LocalCallout(title: paceLabel(s.v), subtitle: timeLabel(s.t))
                                            .position(x: clampedX, y: clampedY)
                                    }
                                }
                            }

                        case .elevation:
                            Chart {
                                ForEach(m.elevationSeries.indices, id: \.self) { i in
                                    let p = m.elevationSeries[i]
                                    LineMark(x: .value("t", p.time), y: .value("m", p.meters))
                                    PointMark(x: .value("t", p.time), y: .value("m", p.meters))
                                        .opacity(selElev?.t == p.time ? 1 : 0)
                                }
                            }
                            .chartYAxis { AxisMarks() }
                            .contentShape(Rectangle())
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    let plot = geo[proxy.plotAreaFrame]
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0).onChanged { value in
                                                let xInPlot = value.location.x - plot.minX
                                                if let xVal: Double = proxy.value(atX: xInPlot) {
                                                    let xs = m.elevationSeries.map { $0.time }
                                                    if let idx = nearestIndex(xVal, in: xs) {
                                                        let p = m.elevationSeries[idx]
                                                        selElev = (p.time, p.meters)
                                                    }
                                                }
                                            }
                                        )
                                    if let s = selElev,
                                       let px = proxy.position(forX: s.t),
                                       let py = proxy.position(forY: s.v) {
                                        let margin: CGFloat = 40
                                        let clampedX = min(max(plot.origin.x + px, plot.minX + margin), plot.maxX - margin)
                                        let clampedY = min(max(plot.origin.y + py - 28, plot.minY - margin/2), plot.maxY - margin/2)
                                        LocalCallout(title: "\(Int(s.v)) m", subtitle: timeLabel(s.t))
                                            .position(x: clampedX, y: clampedY)
                                    }
                                }
                            }

                        case .hr:
                            Chart {
                                ForEach(m.heartRateSeries.indices, id: \.self) { i in
                                    let p = m.heartRateSeries[i]
                                    LineMark(x: .value("t", p.time), y: .value("bpm", p.bpm))
                                    PointMark(x: .value("t", p.time), y: .value("bpm", p.bpm))
                                        .opacity(selHR?.t == p.time ? 1 : 0)
                                }
                            }
                            .chartYAxis { AxisMarks() }
                            .contentShape(Rectangle())
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    let plot = geo[proxy.plotAreaFrame]
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0).onChanged { value in
                                                let xInPlot = value.location.x - plot.minX
                                                if let xVal: Double = proxy.value(atX: xInPlot) {
                                                    let xs = m.heartRateSeries.map { $0.time }
                                                    if let idx = nearestIndex(xVal, in: xs) {
                                                        let p = m.heartRateSeries[idx]
                                                        selHR = (p.time, p.bpm)
                                                    }
                                                }
                                            }
                                        )
                                    if let s = selHR,
                                       let px = proxy.position(forX: s.t),
                                       let py = proxy.position(forY: s.v) {
                                        let margin: CGFloat = 40
                                        let clampedX = min(max(plot.origin.x + px, plot.minX + margin), plot.maxX - margin)
                                        let clampedY = min(max(plot.origin.y + py - 28, plot.minY + margin/2), plot.maxY - margin/2)
                                        LocalCallout(title: "\(Int(s.v)) bpm", subtitle: timeLabel(s.t))
                                            .position(x: clampedX, y: clampedY)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 220)

                    if tabs[safeIndex] == .hr, let a = m.avgHR, let mx = m.maxHR {
                        Text("Avg \(Int(a)) bpm • Max \(Int(mx)) bpm")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func defaultRegion() -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }
}

// Métrica grande y centrada
private struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Mapa con ruta

struct RouteMapView: UIViewRepresentable {
    let coords: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)

        guard coords.count >= 2 else {
            if let c = coords.first {
                let region = MKCoordinateRegion(center: c,
                                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                map.setRegion(region, animated: false)
            }
            return
        }

        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(polyline)

        let rect = polyline.boundingMapRect
        map.setVisibleMapRect(rect,
                              edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                              animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let pl = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: pl)
                r.lineWidth = 5
                r.strokeColor = UIColor.systemBlue
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Gym detail + Insights

struct GymSessionDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [Settings]
    private var usePounds: Bool { settingsList.first?.prefersPounds ?? false }

    let session: StrengthSession

    @State private var showDelete = false
    @State private var showEdit = false

    // Presentación hoja de insights
    @State private var showExercisePicker = false
    @State private var selectedExercise: Exercise? = nil   // usamos sheet(item:)

    var body: some View {
        List {
            Section("SETS") {
                ForEach(sortedSets, id: \.id) { set in
                    GymSetRow(set: set, usePounds: usePounds)
                }
            }

            if let notes = session.notes, !notes.isEmpty {
                Section("NOTES") { Text(notes) }
            }

            Section("SUMMARY") {
                HStack {
                    Text("Date"); Spacer()
                    Text(SummaryView.formatDate(session.date))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Points"); Spacer()
                    Text("\(Int(session.totalPoints)) pts")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // --- INSIGHTS (debajo de SUMMARY: pill) ---
            if !insightExercises.isEmpty {
                Button {
                    if insightExercises.count == 1 {
                        selectedExercise = insightExercises.first  // al asignar, sheet(item:) se presenta
                    } else {
                        showExercisePicker = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.xyaxis.line")
                        Text("Insights").font(.headline)
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .systemBlue).opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
                Button(role: .destructive) { showDelete = true } label: { Text("Delete") }
            }
        }
        .confirmationDialog("Choose exercise",
                            isPresented: $showExercisePicker) {
            ForEach(insightExercises, id: \.id) { ex in
                Button(ex.name) {
                    selectedExercise = ex
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete workout?",
                            isPresented: $showDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(session)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedExercise) { ex in
            // Se presenta SOLO cuando hay ejercicio -> no hay pantalla en blanco
            GymExerciseInsightsView(exercise: ex,
                                    currentSession: session,
                                    usePounds: usePounds,
                                    context: context)
        }
        .sheet(isPresented: $showEdit) {
            EditGymSheet(session: session)
        }
    }

    private var sortedSets: [StrengthSet] {
        session.sets.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            return a.id.uuidString < b.id.uuidString
        }
    }

    private var insightExercises: [Exercise] {
        var seen = Set<UUID>()
        var result: [Exercise] = []
        for set in session.sets {
            let ex = set.exercise
            if !seen.contains(ex.id), hasHistory(for: ex) {
                seen.insert(ex.id); result.append(ex)
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private func hasHistory(for ex: Exercise) -> Bool {
        let desc = FetchDescriptor<StrengthSession>(
            sortBy: [SortDescriptor(\StrengthSession.date, order: .reverse)]
        )
        guard let sessions = try? context.fetch(desc), !sessions.isEmpty else { return false }
        var count = 0
        for s in sessions where s.sets.contains(where: { $0.exercise.id == ex.id }) {
            count += 1; if count >= 2 { return true }
        }
        return false
    }
}

private struct GymSetRow: View {
    let set: StrengthSet
    let usePounds: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(set.exercise.name).font(.headline)
                Text("• \(groupName(set.exercise.muscleGroup))")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
            }
            HStack(spacing: 12) {
                Text("Reps: \(set.reps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let wKg = set.weightKg, wKg > 0 {
                    let value = usePounds ? kgToLb(wKg) : wKg
                    let unit  = usePounds ? "lb" : "kg"
                    let fmt   = usePounds ? "%.0f" : "%.1f"
                    Text("Weight: \(String(format: fmt, value)) \(unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func groupName(_ g: MuscleGroup) -> String {
        switch g {
        case .chestBack: return "Chest/Back"
        case .arms:      return "Arms"
        case .legs:      return "Legs"
        case .core:      return "Core"
        @unknown default: return "Other"
        }
    }
}

// ===== MVVM: ViewModel para Gym Exercise Insights =====

final class GymExerciseInsightsVM: ObservableObject {
    enum Period: String, CaseIterable, Identifiable {
        case ytd = "YTD", monthly = "Monthly", yearly = "Yearly"
        var id: String { rawValue }
    }

    @Published var points: [GymPoint] = []
    @Published var isWeighted = false
    @Published var emptyMessage: String? = nil

    struct GymPoint: Identifiable {
        let id = UUID()
        let date: Date
        let valueKgOrReps: Double
    }

    private let context: ModelContext
    private let exercise: Exercise
    private let refDate: Date

    init(context: ModelContext, exercise: Exercise, refDate: Date) {
        self.context = context
        self.exercise = exercise
        self.refDate = refDate
        self.isWeighted = exercise.isWeighted
    }

    func load(period: Period) {
        let start = startDate(for: period, ref: refDate)
        let end   = refDate

        let pred = #Predicate<StrengthSession> { s in
            s.date >= start && s.date <= end
        }
        let desc = FetchDescriptor<StrengthSession>(
            predicate: pred,
            sortBy: [SortDescriptor(\StrengthSession.date, order: .forward)]
        )

        let sessions = (try? context.fetch(desc)) ?? []

        // Agrupado por día: mejor peso o reps de ese ejercicio
        let cal = Calendar.current
        var dayBest: [Date: Double] = [:]
        for s in sessions {
            let sets = s.sets.filter { $0.exercise.id == exercise.id }
            guard !sets.isEmpty else { continue }
            let day = cal.startOfDay(for: s.date)
            let v: Double = exercise.isWeighted
                ? (sets.compactMap { $0.weightKg }.max() ?? 0)
                : Double(sets.map { $0.reps }.max() ?? 0)
            dayBest[day] = max(dayBest[day] ?? 0, v)
        }

        let series = dayBest.keys.sorted().map { d in
            GymPoint(date: d, valueKgOrReps: dayBest[d] ?? 0)
        }

        if series.count < 2 {
            self.points = []
            self.emptyMessage = "Not enough data to plot"
        } else {
            self.points = series
            self.emptyMessage = nil
        }
    }

    private func startDate(for p: Period, ref: Date) -> Date {
        let cal = Calendar.current
        switch p {
        case .monthly:
            return cal.date(from: cal.dateComponents([.year, .month], from: ref)) ?? ref
        case .ytd:
            return cal.date(from: DateComponents(year: cal.component(.year, from: ref), month: 1, day: 1)) ?? ref
        case .yearly:
            return cal.date(byAdding: .day, value: -365, to: ref) ?? ref
        }
    }
}

// ===== Hoja de Insights (View) =====

private struct GymExerciseInsightsView: View {
    typealias Period = GymExerciseInsightsVM.Period

    @StateObject private var vm: GymExerciseInsightsVM

    let exerciseName: String
    let usePounds: Bool

    @State private var period: Period = .ytd

    // Init explícito para inyectar VM
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
                    Text(vm.isWeighted ? "Max weight per day" : "Max reps per day")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 2)

                if let msg = vm.emptyMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(msg).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Chart(vm.points) { p in
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value(vm.isWeighted ? (usePounds ? "lb" : "kg") : "reps",
                                      displayValue(p.valueKgOrReps))
                        )
                        PointMark(
                            x: .value("Date", p.date),
                            y: .value(vm.isWeighted ? (usePounds ? "lb" : "kg") : "reps",
                                      displayValue(p.valueKgOrReps))
                        )
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .chartYAxis { AxisMarks() }
                    .frame(height: 260)

                    if let last = vm.points.last {
                        let lastStr = vm.isWeighted ? displayWeight(last.valueKgOrReps)
                                                    : String(format: "%.0f reps", last.valueKgOrReps)
                        let bestVal = vm.points.map(\.valueKgOrReps).max() ?? last.valueKgOrReps
                        let bestStr = vm.isWeighted ? displayWeight(bestVal)
                                                    : String(format: "%.0f reps", bestVal)
                        Text("Last: \(lastStr) • Best: \(bestStr)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.load(period: period) }
            .onChange(of: period) { newVal in vm.load(period: newVal) }
        }
    }

    private func displayWeight(_ kg: Double) -> String {
        let val = usePounds ? kgToLb(kg) : kg
        let unit = usePounds ? "lb" : "kg"
        let fmt = usePounds ? "%.0f %@" : "%.1f %@"
        return String(format: fmt, val, unit)
    }

    private func displayValue(_ v: Double) -> Double {
        vm.isWeighted ? (usePounds ? kgToLb(v) : v) : v
    }
}

// Helpers
@inline(__always) private func kgToLb(_ kg: Double) -> Double { kg * 2.2046226218 }
@inline(__always) private func lbToKg(_ lb: Double) -> Double { lb / 2.2046226218 }

// Compat
extension TrainingDetailView {
    init(session: RunningSession)  { self.init(item: .running(session)) }
    init(session: StrengthSession) { self.init(item: .gym(session)) }
}

