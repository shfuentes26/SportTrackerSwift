import SwiftUI
import SwiftData
import HealthKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [Settings]

    @State private var isImporting = false
    @State private var importResult: String?
    @State private var showImportAlert = false

    // Crea el registro de Settings si no existe
    private func ensureSettings() -> Settings {
        if let s = settingsList.first { return s }
        let s = Settings()
        context.insert(s)
        try? context.save()
        return s
    }

    var body: some View {
        let s = ensureSettings()       // siempre tendremos uno
        @Bindable var sb = s           // bindings sobre el modelo Settings

        Form {
            // HealthKit manual import
            Section(header: Text("Integrations")) {
                Button {
                    Task { await importFromAppleHealth() }
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Text("Import from Apple Health")
                    }
                }
                .disabled(isImporting)

                // Si ya tienes una fecha "lastImportDate" en tu manager,
                // cámbialo por esa propiedad. De momento mostramos hora actual a modo informativo.
                Text("Last import: \(Date().formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Navegación a gestión de ejercicios (mantengo el nombre de tu pantalla)
            Section ("Training") {
                NavigationLink("Manage trainings") { ExercisesListScreen() }
            }
            Section ("Goals") {
                NavigationLink("Manage goals") { GoalsSettingsView() }
            }

            // Preferencias de unidades
            Section("Units") {
                Toggle("Show miles (min/mi)", isOn: $sb.prefersMiles)
                Toggle("Show pounds (lb)",    isOn: $sb.prefersPounds)
            }
        }
        .navigationTitle("Settings")
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResult ?? "Operation completed")
        }
        .brandHeaderSpacer()
    }
}

// MARK: - Apple Health Import (logs cortos + fallback de distancia)
extension SettingsView {
    private func importFromAppleHealth() async {
        isImporting = true
        defer { isImporting = false }

        guard HKHealthStore.isHealthDataAvailable() else {
            importResult = "Health no disponible (este dispositivo no permite HealthKit)."
            showImportAlert = true
            return
        }

        do {
            // 1) Autorizar lectura de HealthKit (delegado en tu manager)
            try await HealthKitManager.shared.requestAuthorization()

            // 2) Traer nuevos workouts, filtrar soportados e insertar
            let newWk = try await HealthKitManager.shared.fetchNewWorkouts()
            let supported = HealthKitManager.shared.filterSupported(newWk)
            let insertedWorkouts = try await HealthKitImportService.saveToLocal(supported, context: context)
            if insertedWorkouts > 0 {
                print("[HK] inserted workouts: \(insertedWorkouts)") // LOG corto
            }

            var totalInserted = insertedWorkouts

            // 3) Fallback si no hay workouts reales:
            //    reconstruye sesiones desde distanceWalkingRunning y filtra caminatas
            if insertedWorkouts == 0 {
                let insertedFallback = try await HealthKitImportService.importFromDistanceSamples(
                    context: context,
                    daysBack: 365,
                    gapSeconds: 15*60,
                    minRunSpeedMS: 2.1,   // ≈ 8:00 min/km
                    minDistanceM: 800,    // >= 0.8 km
                    minDurationS: 8*60    // >= 8 min
                )
                if insertedFallback > 0 {
                    print("[HK] inserted from distance samples: \(insertedFallback)") // LOG corto
                }
                totalInserted += insertedFallback
            }

            // 4) Marcar importación finalizada y avisar
            HealthKitManager.shared.markImported()
            importResult = "Importados \(totalInserted) entrenamientos."
        } catch {
            importResult = "Error: \(error.localizedDescription)"
        }
        showImportAlert = true
    }
}
