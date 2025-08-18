import SwiftUI

struct NewView: View {
    var body: some View {
        NavigationStack {
            Text("New")
                .font(.title)
                .fontWeight(.semibold)
        }
        .navigationTitle("New")
    }
}

#Preview { NewView() }
