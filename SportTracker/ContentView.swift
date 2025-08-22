import SwiftUI

// Tab id para poder cambiar de pestaña por código
enum AppTab: Hashable { case summary, gym, new, running, settings }

// Notificación que lanzaremos al guardar
extension Notification.Name {
    static let navigateToSummary = Notification.Name("NavigateToSummary")
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .summary

    var body: some View {
        // ⬇️ ENLAZAMOS EL TABVIEW A selectedTab
        TabView(selection: $selectedTab) {
            SummaryView()
                .tabItem { Image(systemName: "house.fill"); Text("Summary") }
                .tag(AppTab.summary)   // ⬅️ TAG

            GymView()
                .tabItem { Image(systemName: "dumbbell.fill"); Text("Gym") }
                .tag(AppTab.gym)       // ⬅️ TAG

            NewView()
                .tabItem { Image(systemName: "plus.circle.fill"); Text("New") }
                .tag(AppTab.new)       // ⬅️ TAG

            RunningView()
                .tabItem { Image(systemName: "figure.run"); Text("Running") }
                .tag(AppTab.running)   // ⬅️ TAG

            NavigationStack { SettingsView() }
                .brandNavBar()
                .navigationBarTitleDisplayMode(.inline)
                .tabItem { Image(systemName: "gearshape.fill"); Text("Settings") }
                .tag(AppTab.settings)  // ⬅️ TAG
        }
        .tint(.blue)
        // ⬇️ AHORA SÍ, ESTO CAMBIA DE TAB AL RECIBIR LA NOTIFICACIÓN
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSummary)) { _ in
            selectedTab = .summary
        }
    }
}

#Preview { ContentView() }
