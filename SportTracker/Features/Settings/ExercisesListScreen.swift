import SwiftUI
import SwiftData

struct ExercisesListScreen: View {
    var body: some View {
        NavigationStack {
            // Tu vista existente que ya tira de SwiftData (@Query / modelContext)
            ExercisesListView()
                .navigationTitle("Exercises")
                .navigationBarTitleDisplayMode(.inline)
        }
        .brandNavBar()
        .brandHeaderSpacer()
    }
}
