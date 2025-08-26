// TrainingDetailView.swift
import SwiftUI
import MapKit
import CoreLocation
import SwiftData
// La gráfica vive en PaceHistorySection.swift (PaceHistorySection + FullScreenPaceChart)

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

    var body: some View {
        ScrollView {
            // Mapa o ruta
            if let poly = session.routePolyline, !poly.isEmpty {
                let coords = Polyline.decode(poly)
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

    // Formatos básicos (puedes adaptarlos a millas si quieres que todo el detalle siga Settings)
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f km", km)
    }
    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds/3600, m = (seconds%3600)/60, s = seconds%60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    private func formatPace(distanceMeters: Double, durationSeconds: Int) -> String {
        let km = max(distanceMeters / 1000.0, 0.001)
        let spk = Double(durationSeconds) / km
        let m = Int(spk) / 60, s = Int(spk) % 60
        return String(format: "%d:%02d min/km", m, s)
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
