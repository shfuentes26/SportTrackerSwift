import SwiftUI

struct GymView: View {
    var body: some View {
        NavigationStack {
            Text("Gym")
                .font(.title)
                .fontWeight(.semibold)
        }
        .navigationTitle("Gym")
    }
}

#Preview { GymView() }
