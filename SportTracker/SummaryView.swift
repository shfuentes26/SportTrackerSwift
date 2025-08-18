import SwiftUI

struct SummaryView: View {
    var body: some View {
        NavigationStack {
            Text("Summary")
                .font(.title)
                .fontWeight(.semibold)
        }
        .navigationTitle("Summary")
    }
}

#Preview { SummaryView() }
