import SwiftUI

struct RunningView: View {
    var body: some View {
        NavigationStack {
            Text("Running")
                .font(.title)
                .fontWeight(.semibold)
        }
        .navigationTitle("Running")
    }
}

#Preview { RunningView() }
