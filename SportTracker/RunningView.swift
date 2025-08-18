import SwiftUI
import SwiftData

struct RunningView: View {
    @Query(sort: [SortDescriptor(\RunningSession.date, order: .reverse)])
    private var runs: [RunningSession]

    init() {} // evita el init(runs:) sintetizado

    var body: some View {
        NavigationStack {
            List {
                ForEach(runs) { r in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(SummaryView.formatDate(r.date)).font(.headline)
                            Spacer()
                            Text("\(Int(r.totalPoints)) pts").foregroundStyle(.secondary)
                        }
                        Text("\(SummaryView.formatNumber(r.distanceKm)) km • \(SummaryView.formatPace(r.paceSecondsPerKm)) • \(r.durationSeconds/60) min")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Running")
        }
    }
}


#Preview {
    RunningView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
