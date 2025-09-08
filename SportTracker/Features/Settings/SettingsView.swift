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

    // --- Admin: estados de confirmación y progreso ---
    @State private var confirmDeleteAll = false
    @State private var confirmDeleteRunning = false
    @State private var confirmDeleteGym = false
    @State private var isWiping = false
    @State private var wipeResultMessage: String?
    @State private var showWipeResult = false

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

            // Integraciones
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

            // --- Admin ---
            Section("Admin") {
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    if isWiping {
                        ProgressView()
                    } else {
                        Label("Delete all trainings (Running + Gym)", systemImage: "trash")
                    }
                }
                .disabled(isWiping)

                Button(role: .destructive) {
                    confirmDeleteRunning = true
                } label: {
                    Label("Delete all running", systemImage: "trash")
                }
                .disabled(isWiping)

                Button(role: .destructive) {
                    confirmDeleteGym = true
                } label: {
                    Label("Delete all gym", systemImage: "trash")
                }
                .disabled(isWiping)

                Text("These actions delete local data and will also be removed from iCloud on next sync.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // 🔧 Maintenance (si lo reactivas más adelante)
            /*
            if !didRunRoutesBackfillOnce {
                Section("Maintenance") {
                    NavigationLink {
                        MaintenanceToolsView()
                    } label: {
                        Label("Backfill missing routes", systemImage: "wrench.and.screwdriver")
                    }
                }
            } else {
                Section("Maintenance") {
                    HStack {
                        Label("Routes backfill", systemImage: "wrench.and.screwdriver")
                        Spacer()
                        Text("Done").foregroundStyle(.secondary)
                    }
                }
            }
            */
        }
        .navigationTitle("Settings")
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResult ?? "Operation completed")
        }
        .alert("Restart required", isPresented: $showICloudToggleNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please restart the app to apply iCloud changes.")
        }
        // Confirmaciones Admin
        .alert("Delete all trainings?", isPresented: $confirmDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await wipeAllTrainings() } }
        } message: {
            Text("This will permanently delete ALL Running and Gym sessions (including watch details).")
        }
        .alert("Delete all running?", isPresented: $confirmDeleteRunning) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await wipeAllRunning() } }
        } message: {
            Text("This will permanently delete all running sessions and associated watch data.")
        }
        .alert("Delete all gym?", isPresented: $confirmDeleteGym) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await wipeAllGym() } }
        } message: {
            Text("This will permanently delete all gym sessions and sets (exercises catalog will be kept).")
        }
        .alert("Admin", isPresented: $showWipeResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wipeResultMessage ?? "Done")
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

            // 3) SEGUNDO INTENTO (legado)
            if totalInserted == 0 {
                let newWk = try await HealthKitManager.shared.fetchNewWorkouts()
                let supported = HealthKitManager.shared.filterSupported(newWk)
                let insertedLegacy = try await HealthKitImportService.saveToLocal(supported, context: context)
                if insertedLegacy > 0 {
                    print("[HK] inserted legacy workouts (no routes): \(insertedLegacy)")
                }
                totalInserted += insertedLegacy
            }

            // 4) TERCER INTENTO (fallback por muestras)
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

// MARK: - Admin wipes
extension SettingsView {
    @MainActor
    private func wipeAllTrainings() async {
        await performWipe {
            // RUNNING
            try deleteAllRunningObjects()
            // GYM
            try deleteAllGymObjects()
        }
    }

    @MainActor
    private func wipeAllRunning() async {
        await performWipe {
            try deleteAllRunningObjects()
        }
    }

    @MainActor
    private func wipeAllGym() async {
        await performWipe {
            try deleteAllGymObjects()
        }
    }

    // --- helpers ---
    @MainActor
    private func performWipe(_ work: () throws -> Void) async {
        isWiping = true
        defer { isWiping = false }
        do {
            try work()
            try context.save()

            // Opcional: avisar a tu gestor de iCloud para empujar cambios
            #if os(iOS) && CLOUD_SYNC
            // Ajusta al API real de tu CKSyncManager si existe:
            // await CKSyncManager.shared.notifyLocalDatabaseReset()
            #endif

            wipeResultMessage = "Deletion completed."
        } catch {
            wipeResultMessage = "Error: \(error.localizedDescription)"
        }
        showWipeResult = true
    }

    @MainActor
    private func deleteAllRunningObjects() throws {
        // 1) Detalles de watch y sus puntos/splits (cascade en modelo)
        var dFD = FetchDescriptor<RunningWatchDetail>()
        dFD.includePendingChanges = true
        let details = try context.fetch(dFD)
        for d in details { context.delete(d) }

        // 2) Sessions de running
        var rFD = FetchDescriptor<RunningSession>()
        rFD.includePendingChanges = true
        let runs = try context.fetch(rFD)
        for r in runs { context.delete(r) }
    }

    @MainActor
    private func deleteAllGymObjects() throws {
        // 1) Sets
        var setFD = FetchDescriptor<StrengthSet>()
        setFD.includePendingChanges = true
        let sets = try context.fetch(setFD)
        for s in sets { context.delete(s) }

        // 2) Sessions
        var gsFD = FetchDescriptor<StrengthSession>()
        gsFD.includePendingChanges = true
        let gses = try context.fetch(gsFD)
        for g in gses { context.delete(g) }

        // Nota: NO borramos Exercise (catálogo) a propósito
    }
}
