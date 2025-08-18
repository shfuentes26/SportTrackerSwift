import SwiftUI
import SwiftData

struct SummaryView: View {
    @Query(sort: [SortDescriptor(\RunningSession.date, order: .reverse)])
    private var runs: [RunningSession]
    @Query(sort: [SortDescriptor(\StrengthSession.date, order: .reverse)])
    private var gyms: [StrengthSession]

    init() {}

    var body: some View {
        NavigationStack {
            List {
                Section("Past Trainings") {
                    ForEach(pastItems) { item in
                        HStack {
                            Image(systemName: item.icon)
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.trailing).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Summary")
        }
    }

    private var pastItems: [PastItem] {
        let runItems = runs.map { r in
            PastItem(id: "run-\(r.id.uuidString)",
                     date: r.date,
                     icon: "figure.run",
                     title: "Running • \(Self.formatDate(r.date))",
                     subtitle: "\(Self.formatNumber(r.distanceKm)) km • pace \(Self.formatPace(r.paceSecondsPerKm))",
                     trailing: "\(Int(r.totalPoints)) pts")
        }
        let gymItems = gyms.map { s in
            PastItem(id: "gym-\(s.id.uuidString)",
                     date: s.date,
                     icon: "dumbbell.fill",
                     title: "Gym • \(Self.formatDate(s.date))",
                     subtitle: "\(s.sets.count) set(s)",
                     trailing: "\(Int(s.totalPoints)) pts")
        }
        return (runItems + gymItems).sorted { $0.date > $1.date }
    }

    struct PastItem: Identifiable {
        let id: String
        let date: Date
        let icon: String
        let title: String
        let subtitle: String
        let trailing: String
    }

    // MARK: - Formatters
    static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func formatNumber(_ x: Double) -> String {
        let nf = NumberFormatter()
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 0
        return nf.string(from: NSNumber(value: x)) ?? String(format: "%.2f", x)
    }

    static func formatPace(_ secPerKm: Double) -> String {
        guard secPerKm > 0 else { return "--" }
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d min/km", m, s)
    }
}

#Preview {
    SummaryView()
        .modelContainer(try! Persistence.shared.makeModelContainer(inMemory: true))
}
