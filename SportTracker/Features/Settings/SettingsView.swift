import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [Settings]
    
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var showImportAlert = false

    // crea si no existe
    private func ensureSettings() -> Settings {
        if let s = settingsList.first { return s }
        let s = Settings()
        context.insert(s)
        try? context.save()
        return s
    }

    var body: some View {
        let s = ensureSettings()              // siempre tendremos uno
        @Bindable var sb = s                  // para editarlo con bindings

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

                Text("Last import: \(HealthKitManager.shared.lastImportDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // Nueva opción de Exercises
            Section {
                NavigationLink("Manage trainings") { ExercisesListScreen() }
            }

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
    
    private func importFromAppleHealth() async {
            isImporting = true
            defer { isImporting = false }
            do {
                try await HealthKitManager.shared.requestAuthorization()
                let newWk = try await HealthKitManager.shared.fetchNewWorkouts()
                let supported = HealthKitManager.shared.filterSupported(newWk)
                // map to sessions and save
                let inserted = try await HealthKitImportService.saveToLocal(supported, context: context)
                HealthKitManager.shared.markImported()
                importResult = "Importados \(inserted) entrenamientos."
            } catch {
                importResult = "Error: \(error.localizedDescription)"
            }
            showImportAlert = true
        }
}
