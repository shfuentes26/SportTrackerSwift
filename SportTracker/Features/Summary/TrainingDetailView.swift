// TrainingDetailView.swift
import SwiftUI
import MapKit
import CoreLocation
import SwiftData
import Charts
// La gráfica vive en PaceHistorySection.swift (PaceHistorySection + FullScreenPaceChart)

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
    
    /// Convierte un TimeInterval en "hh:mm:ss" (con cero a la izquierda)
    private func timeLabel(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    
    // Índice más cercano por eje X (TimeInterval)
    private func nearestIndex(_ x: Double, in xs: [Double]) -> Int? {
        guard !xs.isEmpty else { return nil }
        var best = 0; var bestDist = abs(xs[0] - x)
        for i in 1..<xs.count {
            let d = abs(xs[i] - x)
            if d < bestDist { best = i; bestDist = d }
        }
        return best
    }
    
    // Qué pestañas (gráficas) hay disponibles según los datos
    private enum AnalysisTab: Int, CaseIterable {
        case pace, elevation, hr
        
        var title: String {
            switch self {
            case .pace:      return "Pace"
            case .elevation: return "Elevation"
            case .hr:        return "HR"
            }
        }
    }
    
    // Devuelve las pestañas que realmente tienen datos
    private func availableTabs(for m: RunMetrics) -> [AnalysisTab] {
        var tabs: [AnalysisTab] = []
        if !m.paceSeries.isEmpty      { tabs.append(.pace) }
        if !m.elevationSeries.isEmpty { tabs.append(.elevation) }
        if !m.heartRateSeries.isEmpty { tabs.append(.hr) }
        return tabs
    }
    
    // Ruta decodificada (opcional)
    private var routeCoords: [CLLocationCoordinate2D]? {
        guard let poly = session.routePolyline, !poly.isEmpty else { return nil }
        return Polyline.decode(poly)
    }
    
    var body: some View {
        ScrollView {
            // Mapa o ruta
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
                // Métricas del run
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
                // ====== MÉTRICAS DETALLADAS (PACE / ELEV / HR) ======
                analysisSection
                // ---- Botón "Insights" (abre gráfico standalone) ----
                if let b = bucket(for: session.distanceMeters / 1000.0) {
                    let pts = fetchPaceHistory(for: b, prefersMiles: useMiles)
                    if pts.count >= 2 {
                        Button {
                            insights = .init(bucket: b, points: pts)
                        } label: {
                            Label("Insights • \(b.display)", systemImage: "chart.xyaxis.line")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .navigationTitle("Running")
        .navigationBarTitleDisplayMode(.large)
        // Presentación del gráfico en pantalla completa
        .sheet(item: $insights) { payload in
            FullScreenPaceChart(bucket: payload.bucket,
                                prefersMiles: useMiles,
                                points: payload.points)
        }
        .task {
            // Señal inequívoca: este run viene de Health (no del Watch)
            let fromHealth = (session.notes ?? "")
                .localizedCaseInsensitiveContains("Imported from Apple Health")

            // Si hay series reales del Watch para esta sesión
            let watchDetail = watchDetailWithSeries()

            #if DEBUG
            print("[Detail] fromHealth:", fromHealth,
                  "watchSeries: HR:", watchDetail?.hrPoints.count ?? 0,
                  "pace:", watchDetail?.pacePoints.count ?? 0,
                  "elev:", watchDetail?.elevationPoints.count ?? 0)
            #endif

            if fromHealth {
                // Para Health, SIEMPRE tiramos de HealthKit
                _ = try? await HealthKitManager.shared.requestAuthorization()
                metrics = try? await HealthKitImportService.fetchRunMetrics(for: session)
            } else if let d = watchDetail {
                // Watch con series guardadas (HR/Pace/Elev locales)
                metrics = metricsFromWatchDetail(detail: d)
            } else {
                // Resto de casos → HealthKit como respaldo
                _ = try? await HealthKitManager.shared.requestAuthorization()
                metrics = try? await HealthKitImportService.fetchRunMetrics(for: session)
            }
            selectedIndex = 0
        }
        .brandHeaderSpacer()
    }
    
    // Serie desde el primer run que cumple la marca hasta el último registrado
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
    
    // Formatos básicos
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f km", km)
    }
    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds/3600, m = (seconds%3600)/60, s = seconds%60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    
    /// Pace en tarjeta superior: respeta Settings (min/km o min/mi)
    private func formatPace(distanceMeters: Double, durationSeconds: Int) -> String {
        let km = max(distanceMeters / 1000.0, 0.001)
        let secPerKm = Double(durationSeconds) / km
        let secPerUnit = useMiles ? secPerKm * 1.609344 : secPerKm // s/mi si miles
        let m = Int(secPerUnit) / 60
        let s = Int(secPerUnit) % 60
        let unit = useMiles ? "min/mi" : "min/km"
        return String(format: "%d:%02d %@", m, s, unit)
    }
    
    /// Etiqueta para valores de pace en el eje Y (mm:ss)
    private func paceLabel(_ secondsPerUnit: Double) -> String {
        let m = Int(secondsPerUnit) / 60
        let s = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d", m, s)
    }
    
    // ====== SOLO TABS CON DATOS ======
    @ViewBuilder
    private var analysisSection: some View {
        if let m = metrics {
            // Construir tabs disponibles dinámicamente
            let tabs = availableTabs(for: m)
            if !tabs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Analysis").font(.headline)
                    
                    // Asegurar índice válido si cambia el set de tabs
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
                    .onChange(of: tabs) { _ in
                        // Si cambian los tabs (por datos que llegan), vuelve al primero
                        selectedIndex = 0
                    }
                    
                    Group {
                        switch tabs[safeIndex] {
                        case .pace:
                            // Serie mostrada: convierte a s/mi si useMiles
                            let paceSeriesDisplayed: [(time: Double, secPerUnit: Double)] =
                            m.paceSeries.map { p in
                                let val = useMiles ? p.secPerKm * 1.609344 : p.secPerKm
                                return (p.time, val)
                            }
                            
                            Chart {
                                ForEach(paceSeriesDisplayed.indices, id: \.self) { i in
                                    let p = paceSeriesDisplayed[i]
                                    LineMark(x: .value("t", p.time),
                                             y: .value(useMiles ? "sec/mi" : "sec/km", p.secPerUnit))
                                    PointMark(x: .value("t", p.time),
                                              y: .value(useMiles ? "sec/mi" : "sec/km", p.secPerUnit))
                                    .opacity(selPace?.t == p.time ? 1 : 0) // resalta el seleccionado
                                }
                            }
                            .chartYAxis {
                                AxisMarks(preset: .extended) { v in
                                    AxisGridLine(); AxisTick()
                                    AxisValueLabel {
                                        if let y = v.as(Double.self) { Text(paceLabel(y)) }
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    let plot = geo[proxy.plotAreaFrame]
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let xInPlot = value.location.x - plot.minX
                                                    if let xVal: Double = proxy.value(atX: xInPlot) {
                                                        let xs = paceSeriesDisplayed.map { $0.time }
                                                        if let idx = nearestIndex(xVal, in: xs) {
                                                            let p = paceSeriesDisplayed[idx]
                                                            selPace = (p.time, p.secPerUnit)
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
                                        LocalCallout(
                                            title: paceLabel(s.v),
                                            subtitle: timeLabel(s.t)
                                        )
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
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
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
                                        let clampedY = min(max(plot.origin.y + py - 28, plot.minY + margin/2), plot.maxY - margin/2)
                                        LocalCallout(
                                            title: "\(Int(s.v)) m",
                                            subtitle: timeLabel(s.t)
                                        )
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
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
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
                                        LocalCallout(
                                            title: "\(Int(s.v)) bpm",
                                            subtitle: timeLabel(s.t)
                                        )
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
            } else {
                // Si no hay ningún dato, no mostramos sección
                EmptyView()
            }
        }
    }
    
    private func defaultRegion() -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }
    
    // 👇 Construye métricas desde lo que ya guardamos al recibir el payload del Watch
    // 👇 Construye métricas desde lo que ya guardamos al recibir el payload del Watch
    private func metricsFromWatchDetail(detail: RunningWatchDetail) -> RunMetrics? {
        // HR
        let hr = detail.hrPoints.sorted { $0.t < $1.t }.map { (time: $0.t, bpm: $0.v) }

        // Pace: tus puntos son velocidad m/s → pace s/km
        let pace = detail.pacePoints
            .sorted { $0.t < $1.t }
            .compactMap { p -> (time: Double, secPerKm: Double)? in
                guard p.v > 0 else { return nil }
                return (time: p.t, secPerKm: 1000.0 / p.v)
            }

        // Elevación
        let elev = detail.elevationPoints
            .sorted { $0.t < $1.t }
            .map { (time: $0.t, meters: $0.v) }
        
        let totalAscent: Double = 0

        // Splits
        let splits: [RunMetrics.Split] = detail.splits
            .sorted { $0.index < $1.index }
            .map { .init(km: Int($0.index), seconds: $0.duration) }

        // HR stats
        let avg = hr.isEmpty ? nil : hr.map(\.bpm).reduce(0, +) / Double(hr.count)
        let mx  = hr.map(\.bpm).max()

        return .init(
            splits: splits,
            paceSeries: pace,
            elevationSeries: elev,
            totalAscent: totalAscent,   // si no existe en tu modelo, usa 0
            heartRateSeries: hr,
            avgHR: avg,
            maxHR: mx
        )
    }
    
    /// ¿Existe un RunningWatchDetail con series para esta sesión?
    private func watchDetailWithSeries() -> RunningWatchDetail? {
        var fd = FetchDescriptor<RunningWatchDetail>()
        fd.fetchLimit = 200
        guard
            let details = try? context.fetch(fd),
            let d = details.first(where: { $0.session?.persistentModelID == session.persistentModelID })
        else { return nil }

        let hasSeries = (!d.hrPoints.isEmpty) || (!d.pacePoints.isEmpty) || (!d.elevationPoints.isEmpty)
        return hasSeries ? d : nil
    }

    /// Señal barata por notas (extra, por si algún día no hubiera enlace SwiftData)
    private var isWatchByNote: Bool {
        (session.notes ?? "").localizedCaseInsensitiveContains("Imported from Apple Watch")
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

// MARK: - Gym detail

struct GymSessionDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let session: StrengthSession

    @State private var showDelete = false
    @State private var showEdit = false

    var body: some View {
        List {
            Section("SETS") {
                ForEach(sortedSets, id: \.id) { set in
                    GymSetRow(set: set)
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
        }
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
                Button(role: .destructive) { showDelete = true } label: { Text("Delete") }
            }
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
}

private struct GymSetRow: View {
    // Lee lb/kg reales desde Settings (SwiftData)
    @Query private var settingsList: [Settings]
    private var usePounds: Bool { settingsList.first?.prefersPounds ?? false }

    let set: StrengthSet

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(set.exercise.name).font(.headline)
                Text("• \(groupName(set.exercise.muscleGroup))")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("Reps: \(set.reps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let wKg = set.weightKg, wKg > 0 {
                    let value = usePounds ? kgToLb(wKg) : wKg
                    let unit  = usePounds ? "lb"      : "kg"
                    let fmt   = usePounds ? "%.0f"    : "%.1f"
                    Text("Weight: \(String(format: fmt, value)) \(unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
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

// Helpers de conversión
@inline(__always) private func kgToLb(_ kg: Double) -> Double { kg * 2.2046226218 }
@inline(__always) private func lbToKg(_ lb: Double) -> Double { lb / 2.2046226218 }

// Compat: permite seguir usando init(session:)
extension TrainingDetailView {
    init(session: RunningSession)  { self.init(item: .running(session)) }
    init(session: StrengthSession) { self.init(item: .gym(session)) }
}
