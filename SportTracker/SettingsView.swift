import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Settings")
                .font(.title)
                .fontWeight(.semibold)
        }
        .navigationTitle("Settings")
    }
}

#Preview { SettingsView() }
