import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [Settings]

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
            // 👇 Nueva opción de Exercises
            Section {
                NavigationLink("Exercises") { ExercisesListScreen() }
            }

            Section("Units") {
                Toggle("Show miles (min/mi)", isOn: $sb.prefersMiles)
                Toggle("Show pounds (lb)",    isOn: $sb.prefersPounds)
            }
        }
        .navigationTitle("Settings")
    }
}
