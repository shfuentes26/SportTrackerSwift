//
//  RunningSessionDetail.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/1/25.
//
import SwiftUI
import MapKit
import CoreLocation
import SwiftData
import Charts

typealias RunMetrics = HealthKitImportService.RunMetrics

struct RunningSessionDetail: View {
    let session: RunningSession
    @State private var region = MKCoordinateRegion()

    @Environment(\.modelContext) private var context
    @Query private var settingsList: [Settings]
    private var useMiles: Bool { settingsList.first?.prefersMiles ?? false }

    // Insights (full screen)
    @State private var insights: InsightsPayload? = nil
    private struct InsightsPayload: Identifiable {
        let id = UUID()
        let bucket: RecordBucket
        let points: [PacePoint]
    }

    @State private var metrics: RunMetrics? = nil
    @State private var selectedIndex: Int = 0

    @State private var selPace: (t: TimeInterval, v: Double)? = nil
    @State private var selElev: (t: TimeInterval, v: Double)? = nil
    @State private var selHR:   (t: TimeInterval, v: Double)? = nil

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

    private func timeLabel(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    private func nearestIndex(_ x: Double, in xs: [Double]) -> Int? {
        guard !xs.isEmpty else { return nil }
        var best = 0; var bestDist = abs(xs[0] - x)
        for i in 1..<xs.count { let d = abs(xs[i] - x); if d < bestDist { best = i; bestDist = d } }
        return best
    }
    private enum AnalysisTab: Int, CaseIterable { case pace, elevation, hr
        var title: String { self == .pace ? "Pace" : (self == .elevation ? "Elevation" : "HR") }
    }
    private func availableTabs(for m: RunMetrics) -> [AnalysisTab] {
        var t: [AnalysisTab] = []
        if !m.paceSeries.isEmpty      { t.append(.pace) }
        if !m.elevationSeries.isEmpty { t.append(.elevation) }
        if !m.heartRateSeries.isEmpty { t.append(.hr) }
        return t
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
                Metric(value: formatPace(distanceMeters: session.distanceMeters, durationSeconds: session.durationSeconds),
                       label: "Pace")

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

                // Botón "Insights" (pill)
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
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .systemBlue).opacity(0.12)))
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
        .sheet(item: $insights) { p in
            FullScreenPaceChart(bucket: p.bucket, prefersMiles: useMiles, points: p.points)
        }
        .task {
            metrics = try? await HealthKitImportService.fetchRunMetrics(for: session)
            selectedIndex = 0
        }
    }

    // MARK: helpers
    private func fetchPaceHistory(for bucket: RecordBucket, prefersMiles: Bool) -> [PacePoint] {
        let minMeters = bucket.km * 1000.0
        let pred = #Predicate<RunningSession> { $0.distanceMeters >= minMeters }
        let desc = FetchDescriptor<RunningSession>(
            predicate: pred,
            sortBy: [SortDescriptor(\RunningSession.date, order: .forward)]
        )
        let runs = (try? context.fetch(desc)) ?? []
        return runs.map { r in
            let km = max(r.distanceMeters / 1000.0, 0.001)
            let pace = pacePerUnit(seconds: Double(r.durationSeconds),
                                   distanceKm: km, prefersMiles: prefersMiles)
            return PacePoint(date: r.date, paceSecPerUnit: pace)
        }
    }
    private func formatDistance(_ m: Double) -> String { String(format: "%.2f km", m / 1000.0) }
    private func formatElapsed(_ s: Int) -> String { String(format: "%d:%02d:%02d", s/3600, (s%3600)/60, s%60) }
    private func formatPace(distanceMeters: Double, durationSeconds: Int) -> String {
        let km = max(distanceMeters / 1000.0, 0.001)
        let secPerKm = Double(durationSeconds) / km
        let secPerUnit = useMiles ? secPerKm * 1.609344 : secPerKm
        let m = Int(secPerUnit)/60, s = Int(secPerUnit)%60
        return String(format: "%d:%02d %@", m, s, useMiles ? "min/mi" : "min/km")
    }
    private func paceLabel(_ sec: Double) -> String { String(format: "%d:%02d", Int(sec)/60, Int(sec)%60) }

    @ViewBuilder private var analysisSection: some View {
        if let m = metrics {
            let tabs = availableTabs(for: m)
            if !tabs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Analysis").font(.headline)

                    let safe = min(selectedIndex, max(tabs.count-1, 0))
                    Picker("", selection: Binding(get: { safe }, set: { selectedIndex = $0 })) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { i, t in Text(t.title).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: tabs) { _ in selectedIndex = 0 }

                    Group {
                        switch tabs[safe] {
                        case .pace:
                            let series = m.paceSeries.map { p -> (Double, Double) in
                                (p.time, useMiles ? p.secPerKm * 1.609344 : p.secPerKm)
                            }
                            Chart {
                                ForEach(series.indices, id: \.self) { i in
                                    let p = series[i]
                                    LineMark(x: .value("t", p.0), y: .value(useMiles ? "sec/mi" : "sec/km", p.1))
                                    PointMark(x: .value("t", p.0), y: .value(useMiles ? "sec/mi" : "sec/km", p.1))
                                        .opacity(selPace?.t == p.0 ? 1 : 0)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(preset: .extended) { v in
                                    AxisGridLine(); AxisTick()
                                    AxisValueLabel { if let y = v.as(Double.self) { Text(paceLabel(y)) } }
                                }
                            }
                            .contentShape(Rectangle())
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    let plot = geo[proxy.plotAreaFrame]
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                            let xInPlot = value.location.x - plot.minX
                                            if let xVal: Double = proxy.value(atX: xInPlot) {
                                                let xs = series.map { $0.0 }
                                                if let idx = nearestIndex(xVal, in: xs) {
                                                    let p = series[idx]; selPace = (p.0, p.1)
                                                }
                                            }
                                        })
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
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                            let xInPlot = value.location.x - plot.minX
                                            if let xVal: Double = proxy.value(atX: xInPlot) {
                                                let xs = m.elevationSeries.map { $0.time }
                                                if let idx = nearestIndex(xVal, in: xs) {
                                                    let p = m.elevationSeries[idx]; selElev = (p.time, p.meters)
                                                }
                                            }
                                        })
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
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                            let xInPlot = value.location.x - plot.minX
                                            if let xVal: Double = proxy.value(atX: xInPlot) {
                                                let xs = m.heartRateSeries.map { $0.time }
                                                if let idx = nearestIndex(xVal, in: xs) {
                                                    let p = m.heartRateSeries[idx]; selHR = (p.time, p.bpm)
                                                }
                                            }
                                        })
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

                    if tabs[safe] == .hr, let a = m.avgHR, let mx = m.maxHR {
                        Text("Avg \(Int(a)) bpm • Max \(Int(mx)) bpm")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func defaultRegion() -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                           span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    }
}

// Métrica grande centrada
struct Metric: View {
    let value: String; let label: String
    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }
}

// Mapa con ruta (reutilizable)
struct RouteMapView: UIViewRepresentable {
    let coords: [CLLocationCoordinate2D]
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.showsCompass = false; map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard coords.count >= 2 else {
            if let c = coords.first {
                map.setRegion(MKCoordinateRegion(center: c,
                                                 span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)),
                              animated: false)
            }
            return
        }
        let pl = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(pl)
        let rect = pl.boundingMapRect
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let pl = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: pl)
            r.lineWidth = 5; r.strokeColor = UIColor.systemBlue; r.lineJoin = .round; r.lineCap = .round
            return r
        }
    }
}

