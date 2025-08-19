import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SummaryView()
                .tabItem { Image(systemName: "house.fill"); Text("Summary") }
            GymView()
                .tabItem { Image(systemName: "dumbbell.fill"); Text("Gym") }
            NewView()
                .tabItem { Image(systemName: "plus.circle.fill"); Text("New") }
            RunningView()
                .tabItem { Image(systemName: "figure.run"); Text("Running") }
            NavigationStack { SettingsView() }  
                .tabItem { Image(systemName: "gearshape.fill"); Text("Settings") }
        }
        .tint(.blue)
    }
}

#Preview { ContentView() }
