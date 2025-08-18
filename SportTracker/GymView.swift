import SwiftUI
import SwiftData

struct GymView: View {
    @Query(sort: [SortDescriptor(\StrengthSession.date, order: .reverse)])
    private var sessions: [StrengthSession]

    init() {}

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { s in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(SummaryView.formatDate(s.date)).font(.headline)
                            Spacer()
                            Text("\(Int(s.totalPoints)) pts").foregroundStyle(.secondary)
                        }
                        Text("\(s.sets.count) set(s)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Gym")
        }
    }
}

#Preview {
    GymView().modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
