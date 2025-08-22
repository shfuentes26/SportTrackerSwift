import SwiftUI
import MapKit
import CoreLocation

// Unifica ambos tipos de detalle
enum TrainingItem {
    case running(RunningSession)
    case gym(StrengthSession)      // ← usa StrengthSession (no existe GymSession)
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

    var body: some View {
        ScrollView {
            // Mapa con ruta si existe
            if let poly = session.routePolyline, !poly.isEmpty {
                let coords = Polyline.decode(poly)   // ← usa el Polyline ya definido en RunningLiveManager.swift
                RouteMapView(coords: coords)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            } else {
                // Mapa básico sin ruta (centrado genérico)
                Map(coordinateRegion: $region)
                    .onAppear { region = defaultRegion() }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            }

            // Métricas
            VStack(spacing: 20) {
                Metric(value: formatDistance(session.distanceMeters), label: "Distance")
                Metric(value: formatElapsed(session.durationSeconds), label: "Time")
                Metric(value: formatPace(distanceMeters: session.distanceMeters,
                                         durationSeconds: session.durationSeconds),
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
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .navigationTitle("Running")
        .navigationBarTitleDisplayMode(.large)
    }

    // Helpers de formato (km/min/km por defecto)
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
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                           span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
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

// MARK: - Mapa con ruta (funciona iOS 15+ usando MKMapView)

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

        // encuadre con padding
        let rect = polyline.boundingMapRect
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
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


// MARK: - Gym detail (mejorado)
import SwiftData // asegúrate de tenerlo arriba del archivo

// MARK: - Gym detail (mejorado y con type-check ligero)
struct GymSessionDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let session: StrengthSession

    @State private var showDelete = false
    @State private var showEdit = false

    var body: some View {
        List {
            // 1) Sets (tipo + grupo) → reps/peso
            Section("Sets") {
                ForEach(sortedSets, id: \.id) { set in
                    GymSetRow(set: set)        // ← subvista pequeña = el type-check va rápido
                }
            }

            // 2) Notas (si hay)
            if let notes = session.notes, !notes.isEmpty {
                Section("Notes") { Text(notes) }
            }

            // 3) Fecha y puntos
            Section("Summary") {
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
            EditGymSheet(session: session)   // ← el editor completo que ya existe
        }
    }

    // MARK: Helpers
    private var sortedSets: [StrengthSet] {
        session.sets.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

// Fila pequeña para cada set (reduce complejidad del body principal)
private struct GymSetRow: View {
    let set: StrengthSet

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tipo de ejercicio + grupo
            HStack {
                Text(set.exercise.name).font(.headline)
                Text("• \(groupName(set.exercise.muscleGroup))")
                    .foregroundStyle(.secondary)
            }

            // Reps y peso (si hay)
            HStack(spacing: 12) {
                Text("Reps: \(set.reps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let w = set.weightKg, w > 0 {
                    Text("Weight: \(String(format: "%.1f", w)) kg")
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
// Editor simple (fecha + notas) para Strength; se puede ampliar luego
struct EditStrengthNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State var session: StrengthSession
    @State private var date: Date
    @State private var notes: String

    init(session: StrengthSession) {
        _session = State(initialValue: session)
        _date = State(initialValue: session.date)
        _notes = State(initialValue: session.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Edit Gym")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        session.date = date
        session.notes = notes.isEmpty ? nil : notes
        try? context.save()
        dismiss()
    }
}
