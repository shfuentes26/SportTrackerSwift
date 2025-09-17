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
    
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showDelete = false
    
    // Splits/metrics para “Records” (mejor ventana contigua)
    @State private var runMetrics: HealthKitImportService.RunMetrics? = nil

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
    
    @ViewBuilder
    private var splitsSection: some View {
        if let s = metrics?.splits, !s.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Splits").font(.headline)
                ForEach(s) { sp in
                    HStack {
                        Text("\(sp.km)K")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, alignment: .leading)
                        Spacer()
                        Text(paceLabel(sp.seconds))        // mm:ss
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    // Mapa “deshabilitado”
                    .grayscale(1.0)
                    .saturation(0)
                    .overlay(
                        HStack(spacing: 8) {
                            Image(systemName: "map")
                            Text("No route recorded")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.secondary)
                        .background(.ultraThinMaterial, in: Capsule())
                        , alignment: .center
                    )
                    .allowsHitTesting(false)
            }
            

            VStack(spacing: 20) {
                Metric(value: formatDistance(session.distanceMeters), label: "Distance")
                Metric(value: formatElapsed(session.durationSeconds), label: "Time")
                Metric(value: formatPace(distanceMeters: session.distanceMeters, durationSeconds: session.durationSeconds),
                       label: "Pace")

                Text("\(Int(session.totalPoints)) pts • \(SummaryView.formatDate(session.date))")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                // Badges del propio run
                let allRuns = fetchAllRuns()
                let mainBadges = RunRecords.badges(for: session, among: allRuns, top: 3, minFactor: 1.0)
                /*if !mainBadges.isEmpty {
                    RecordBadgesRow(badges: mainBadges)
                }*/
                
                if let notes = session.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(.headline)
                        Text(notes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Records (bucket principal + menores) con tiempo y pace
                let rows = recordRows(for: session, among: allRuns, metrics: runMetrics)
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Records")
                            .font(.headline)
                            .padding(.top, 6)

                        ForEach(rows) { row in
                            HStack(spacing: 8) {
                                // Distancia (1K, 3K, 5K...)
                                Text(bucketLabel(row.bucketKm))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 64, alignment: .leading)

                                // Badges (BR y/o YY)
                                RecordBadgesRow(badges: row.badges)

                                Spacer()

                                // Tiempo + pace para esa distancia
                                Text("\(formatElapsed(row.durationSec)) • \(row.paceText)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                // 2) Añade este ViewBuilder en la vista:
                splitsSection

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
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
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
            EditRunningSheet(run: session)
        }
        .brandHeaderSpacer()
        .navigationTitle("Running")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $insights) { p in
            FullScreenPaceChart(bucket: p.bucket, prefersMiles: useMiles, points: p.points)
        }
        .task {
            metrics = try? await HealthKitImportService.fetchRunMetrics(for: session)
            selectedIndex = 0
        }
        .onAppear {
            Task { // lectura “solo UI”: no modifica BD
                runMetrics = try? await HealthKitImportService.fetchRunMetrics(for: session)
                    print("Splits count: \(metrics?.splits.count ?? -1)")
            }
        }
    }
    
    // MARK: - Badges UI
    
    // Fila para la lista de records
    private struct RecordListItem: Identifiable {
        let id = UUID()
        let bucketKm: Double
        let badges: [RecordBadgeModel]
        let durationSec: Int
        let paceText: String
    }

    /// Construye las filas de records para el bucket principal y los menores
    /// - Si hay splits: usa mejor ventana contigua; si no, pace medio.
    private func recordRows(for run: RunningSession,
                            among runs: [RunningSession],
                            metrics: HealthKitImportService.RunMetrics?) -> [RecordListItem] {
        let km = run.distanceMeters / 1000.0
        guard let mainBucket = RunRecords.assignBucketKm(for: km, minFactor: 1.0) else { return [] }

        var out: [RecordListItem] = []

        // 1) Bucket principal (badges reales de RunRecords) + tiempo “exacto” del bucket
        let mainBadges = RunRecords.badges(for: run, among: runs, top: 3, minFactor: 1.0)
        if !mainBadges.isEmpty {
            let mainSec: Int
            if let splits = metrics?.splits,
               let best = bestRollingSeconds(forKilometers: Int(mainBucket.rounded()), splits: splits) {
                mainSec = Int(best.rounded())
            } else {
                let sessionPace = paceSecPerKm(run)
                mainSec = Int((sessionPace * mainBucket).rounded())
            }
            out.append(RecordListItem(bucketKm: mainBucket,
                                      badges: mainBadges,
                                      durationSec: mainSec,
                                      paceText: formatPace(distanceMeters: mainBucket * 1000.0, durationSeconds: mainSec)))
        }

        // 2) Buckets menores (1K,3K,5K...) — splits o fallback al pace medio
        let standards: [Double] = [1.0, 3.0, 5.0, 10.0, 21.0975, 42.195]
        let targets = standards.filter { $0 < mainBucket }

        let sessionPace = paceSecPerKm(run)
        let splits = metrics?.splits ?? []

        for b in targets {
            let seconds: Int
            if !splits.isEmpty, let best = bestRollingSeconds(forKilometers: Int(b.rounded()), splits: splits) {
                seconds = Int(best.rounded())
            } else {
                seconds = Int((sessionPace * b).rounded())
            }

            // Badges “virtuales” usando ese tiempo para competir en el bucket b
            let badges = subordinateBadgesUsing(seconds: seconds, bucketKm: b, for: run, among: runs)
            if !badges.isEmpty {
                out.append(RecordListItem(bucketKm: b,
                                          badges: badges,
                                          durationSec: seconds,
                                          paceText: formatPace(distanceMeters: b * 1000.0, durationSeconds: seconds)))
            }
        }

        // Ordena por distancia descendente: primero principal (mayor)
        out.sort { $0.bucketKm > $1.bucketKm }
        return out
    }

    private struct RecordBadgesRow: View {
        let badges: [RecordBadgeModel]
        var body: some View {
            HStack(spacing: 4) {
                ForEach(badges) { b in
                    ZStack {
                        Circle()
                            .fill(color(for: b))
                            .frame(width: 18, height: 18)
                        Text(text(for: b))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
        }
        private func color(for b: RecordBadgeModel) -> Color {
            switch b.kind {
            case .absolute(let rank, _), .yearly(let rank, _, _):
                switch rank {
                case 1: return .yellow   // oro
                case 2: return .gray     // plata
                case 3: return .brown    // bronce
                default: return .secondary
                }
            }
        }
        private func text(for b: RecordBadgeModel) -> String {
            switch b.kind {
            case .absolute:               return "BR"               // Best Record absoluto
            case .yearly(_, let y, _):    return String(y % 100)    // “25” para 2025
            }
        }
    }

    // MARK: - Badges helpers (data)
    private func fetchAllRuns() -> [RunningSession] {
        let desc = FetchDescriptor<RunningSession>(
            sortBy: [SortDescriptor(\RunningSession.date, order: .reverse)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    private func bucketLabel(_ km: Double) -> String {
        switch km {
        case 1.0: return "1K"
        case 3.0: return "3K"
        case 5.0: return "5K"
        case 10.0: return "10K"
        case 21.0975: return "Half"
        case 42.195: return "Marathon"
        default: return String(format: "%.1fK", km)
        }
    }

    private func paceSecPerKm(_ r: RunningSession) -> Double {
        let km = max(r.distanceMeters / 1000.0, 0.001)
        return Double(r.durationSeconds) / km
    }

    // (versión previa por pace medio; la dejamos para compatibilidad si la necesitas en otro sitio)
    private struct SubBadgeRow: Identifiable {
        let id = UUID()
        let bucket: Double
        let badges: [RecordBadgeModel]
    }
    private func subordinateBadges(for run: RunningSession, among runs: [RunningSession]) -> [SubBadgeRow] {
        let km = run.distanceMeters / 1000.0
        guard let mainBucket = RunRecords.assignBucketKm(for: km, minFactor: 1.0) else { return [] }

        let standards: [Double] = [1.0, 3.0, 5.0, 10.0, 21.0975, 42.195]
        let targets = standards.filter { $0 < mainBucket }

        let sessionPace = paceSecPerKm(run)
        let year = Calendar.current.component(.year, from: run.date)

        var out: [SubBadgeRow] = []

        for b in targets {
            // Todos los runs que compiten en el bucket b
            let sameBucket = runs.filter { r in
                let rkm = r.distanceMeters / 1000.0
                return RunRecords.assignBucketKm(for: rkm, minFactor: 1.0) == b
            }

            // Ranking con runs reales + run actual "virtual" (pace medio)
            struct Key { let pace: Double; let duration: Int; let date: Date; let isSession: Bool }
            var arr: [Key] = sameBucket.map { r in
                Key(pace: paceSecPerKm(r), duration: r.durationSeconds, date: r.date, isSession: false)
            }
            let virtualDuration = Int((sessionPace * b).rounded())
            arr.append(Key(pace: sessionPace, duration: virtualDuration, date: run.date, isSession: true))

            arr.sort {
                if $0.pace != $1.pace { return $0.pace < $1.pace }
                if $0.duration != $1.duration { return $0.duration < $1.duration }
                return $0.date > $1.date
            }

            var badges: [RecordBadgeModel] = []
            if let idx = arr.firstIndex(where: { $0.isSession }) {
                let rank = idx + 1
                if rank <= 3 { badges.append(.init(kind: .absolute(rank: rank, bucketKm: b))) }
            }

            let arrYear = arr.filter { k in
                k.isSession || Calendar.current.component(.year, from: k.date) == year
            }
            if let idxY = arrYear.firstIndex(where: { $0.isSession }) {
                let rankY = idxY + 1
                if rankY <= 3 { badges.append(.init(kind: .yearly(rank: rankY, year: year, bucketKm: b))) }
            }

            if !badges.isEmpty {
                out.append(SubBadgeRow(bucket: b, badges: badges))
            }
        }

        return out
    }

    // --- Nuevos helpers para splits ---

    /// Mejor ventana contigua de `k` km usando los splits de HealthKit.
    private func bestRollingSeconds(forKilometers k: Int,
                                    splits: [HealthKitImportService.RunMetrics.Split]) -> Double? {
        guard k >= 1, splits.count >= k else { return nil }
        var best = splits.prefix(k).reduce(0.0) { $0 + $1.seconds }
        var cur = best
        for i in k..<splits.count {
            cur += splits[i].seconds
            cur -= splits[i - k].seconds
            if cur < best { best = cur }
        }
        print("[UI][Best] k=\(k) best=\(best)")
        return best > 0 ? best : nil   // <-- evita 0
    }


    /// Calcula badges “virtuales” para el run actual compitiendo en `bucketKm` con un tiempo dado (segundos).
    private func subordinateBadgesUsing(seconds: Int,
                                        bucketKm b: Double,
                                        for run: RunningSession,
                                        among runs: [RunningSession]) -> [RecordBadgeModel] {
        // Runs que compiten en el bucket b (regla: mayor ≤ distancia)
        let sameBucket = runs.filter { r in
            let rkm = r.distanceMeters / 1000.0
            return RunRecords.assignBucketKm(for: rkm, minFactor: 1.0) == b
        }

        struct Key { let pace: Double; let duration: Int; let date: Date; let isSession: Bool }
        var arr: [Key] = sameBucket.map { r in
            let pace = paceSecPerKm(r)
            return Key(pace: pace, duration: r.durationSeconds, date: r.date, isSession: false)
        }

        // run actual “como si fuera” b km con 'seconds'
        let paceVirtual = Double(seconds) / max(b, 0.001)
        arr.append(Key(pace: paceVirtual, duration: seconds, date: run.date, isSession: true))

        // Orden: mejor pace → menor duración → fecha más reciente (igual que RunRecords)
        arr.sort {
            if $0.pace != $1.pace { return $0.pace < $1.pace }
            if $0.duration != $1.duration { return $0.duration < $1.duration }
            return $0.date > $1.date
        }

        var badges: [RecordBadgeModel] = []

        // Absoluto top-3
        if let idx = arr.firstIndex(where: { $0.isSession }) {
            let rank = idx + 1
            if rank <= 3 { badges.append(.init(kind: .absolute(rank: rank, bucketKm: b))) }
        }

        // Anual top-3 (año del propio run)
        let year = Calendar.current.component(.year, from: run.date)
        let arrYear = arr.filter { k in
            k.isSession || Calendar.current.component(.year, from: k.date) == year
        }
        if let idxY = arrYear.firstIndex(where: { $0.isSession }) {
            let rankY = idxY + 1
            if rankY <= 3 { badges.append(.init(kind: .yearly(rank: rankY, year: year, bucketKm: b))) }
        }

        return badges
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

import SwiftUI
import SwiftData

struct EditRunningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State var run: RunningSession

    @State private var date: Date
    @State private var distanceKm: String
    @State private var hh: String
    @State private var mm: String
    @State private var ss: String
    @State private var notes: String

    init(run: RunningSession) {
        _run = State(initialValue: run)
        _date = State(initialValue: run.date)

        // distancia con 0–2 decimales
        let nf = NumberFormatter()
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 0
        _distanceKm = State(initialValue: nf.string(from: NSNumber(value: run.distanceKm)) ?? String(format: "%.2f", run.distanceKm))

        let total = run.durationSeconds
        _hh = State(initialValue: String(total / 3600))
        _mm = State(initialValue: String((total % 3600) / 60))
        _ss = State(initialValue: String(total % 60))
        _notes = State(initialValue: run.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    TextField("Distance (km)", text: $distanceKm)
                        .keyboardType(.decimalPad)
                    Text("km").foregroundStyle(.secondary)
                }
                Section("Duration (hh:mm:ss)") {
                    HStack(spacing: 6) {
                        TextField("hh", text: $hh).keyboardType(.numberPad).frame(width: 52).multilineTextAlignment(.center)
                        Text(":").monospacedDigit()
                        TextField("mm", text: $mm).keyboardType(.numberPad).frame(width: 42).multilineTextAlignment(.center)
                        Text(":").monospacedDigit()
                        TextField("ss", text: $ss).keyboardType(.numberPad).frame(width: 42).multilineTextAlignment(.center)
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Edit Running")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        let dist = Double(distanceKm.replacingOccurrences(of: ",", with: ".")) ?? 0
        let H = Int(hh) ?? 0, M = Int(mm) ?? 0, S = Int(ss) ?? 0
        let sec = H*3600 + M*60 + S
        guard dist > 0, sec > 0 else { return }

        run.date = date
        run.distanceMeters = dist * 1000
        run.durationSeconds = sec
        run.notes = notes.isEmpty ? nil : notes

        // Recalcular puntos con Settings
        let settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
        if settings.persistentModelID == nil { context.insert(settings) }
        run.totalPoints = PointsCalculator.score(running: run, settings: settings)

        try? context.save()
        dismiss()
    }
}
