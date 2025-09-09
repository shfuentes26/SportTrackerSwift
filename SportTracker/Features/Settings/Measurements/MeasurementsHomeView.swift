import SwiftUI
import SwiftData

struct MeasurementsHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\BodyMeasurement.date, order: .reverse)])
    private var all: [BodyMeasurement]

    @Query private var settingsList: [Settings]
    private var prefersPounds: Bool { settingsList.first?.prefersPounds ?? false }
    private var prefersInches: Bool { false }

    private var latestByKind: [(MeasurementKind, BodyMeasurement?)] {
        MeasurementKind.allCases.map { kind in
            let latest = all.first(where: { $0.kind == kind })
            return (kind, latest)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(latestByKind, id: \.0) { (kind, last) in
                    NavigationLink {
                        MeasurementHistoryView(kind: kind)
                    } label: {
                        HStack {
                            Text(kind.displayName)
                            Spacer()
                            Text(lastValueText(last))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    AddMeasurementView()
                } label: {
                    Label("Add measurement", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Measurements")
    }

    private func lastValueText(_ m: BodyMeasurement?) -> String {
        guard let m else { return "—" }
        if m.kind.isLength {
            return MeasurementFormatters.formatLength(cm: m.value, prefersInches: prefersInches)
        } else {
            return MeasurementFormatters.formatWeight(kg: m.value, prefersPounds: prefersPounds)
        }
    }
}
