import SwiftUI
import SwiftData
import HealthKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [Settings]

    @State private var isImporting = false
    @State private var importResult: String?
    @State private var showImportAlert = false

    // 🔒 Ocultar Maintenance cuando el backfill ya se ejecutó una vez
    @AppStorage("didRunRoutesBackfillOnce") private var didRunRoutesBackfillOnce = false
    
    // ✅ Preferencia de iCloud (no requiere cambios de modelo)
      @AppStorage("useICloudSync") private var useICloudSync = false
      @State private var showICloudToggleNote = false


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
            // STORAGE / SYNC
            Section("Storage & Sync") {
                Toggle("Sync with iCloud", isOn: $useICloudSync)
                    .onChange(of: useICloudSync) { _, _ in
                        // Nota: el contenedor SwiftData se crea al arrancar.
                        // Cambiar esta opción requiere reiniciar la app para re-crear el container.
                        showICloudToggleNote = true
                    }
                Text(useICloudSync ? "iCloud sync: ON" : "iCloud sync: OFF")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

            // Navegación a gestión de ejercicios
            Section("Training") {
                NavigationLink("Manage trainings") { ExercisesListScreen() }
            }
            Section("Goals") {
                NavigationLink("Manage goals") { GoalsSettingsView() }
            }

            // Preferencias de unidades
            Section("Units") {
                Toggle("Show miles (min/mi)", isOn: $sb.prefersMiles)
                Toggle("Show pounds (lb)",    isOn: $sb.prefersPounds)
            }

            // 🔧 Maintenance (oculto cuando ya se ejecutó el backfill)
            /*if !didRunRoutesBackfillOnce {
                Section("Maintenance") {
                    NavigationLink {
                        MaintenanceToolsView()
                    } label: {
                        Label("Backfill missing routes", systemImage: "wrench.and.screwdriver")
                    }
                }
            } else {
                // (Opcional) Muestra estado de que ya se ejecutó
                Section("Maintenance") {
                    HStack {
                        Label("Routes backfill", systemImage: "wrench.and.screwdriver")
                        Spacer()
                        Text("Done").foregroundStyle(.secondary)
                    }
                }
            }*/
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
            importResult = "Health not available (This device doesn't allow HealthKit)."
            showImportAlert = true
            return
        }

        do {
            // 1) Autorizar lectura
            try await HealthKitManager.shared.requestAuthorization()

            // 2) PRIMER INTENTO: traer HKWorkout "reales" (permiten leer HKWorkoutRoute)
            let hkWorkouts = try await HealthKitManager.shared.fetchNewHKWorkouts()
            let insertedWithRoutes = try await HealthKitImportService.saveHKWorkoutsToLocal(
                hkWorkouts,
                context: context
            )
            if insertedWithRoutes > 0 {
                print("[HK] inserted workouts with routes: \(insertedWithRoutes)")
            }

            var totalInserted = insertedWithRoutes

            // 3) SEGUNDO INTENTO (legado): si no llegó nada, usar tu flujo previo (sin rutas)
            if totalInserted == 0 {
                let newWk = try await HealthKitManager.shared.fetchNewWorkouts()
                let supported = HealthKitManager.shared.filterSupported(newWk)
                let insertedLegacy = try await HealthKitImportService.saveToLocal(supported, context: context)
                if insertedLegacy > 0 {
                    print("[HK] inserted legacy workouts (no routes): \(insertedLegacy)")
                }
                totalInserted += insertedLegacy
            }

            // 4) TERCER INTENTO (fallback por muestras): reconstruir desde distanceWalkingRunning
            if totalInserted == 0 {
                let insertedFallback = try await HealthKitImportService.importFromDistanceSamples(
                    context: context,
                    daysBack: 365,
                    gapSeconds: 15*60,
                    minRunSpeedMS: 2.1,
                    minDistanceM: 800,
                    minDurationS: 8*60
                )
                if insertedFallback > 0 {
                    print("[HK] inserted from distance samples: \(insertedFallback)")
                }
                totalInserted += insertedFallback
            }

            // 5) Cierre
            HealthKitManager.shared.markImported()
            importResult = "Imported \(totalInserted) trainings."
        } catch {
            importResult = "Error: \(error.localizedDescription)"
        }
        showImportAlert = true
    }
}
