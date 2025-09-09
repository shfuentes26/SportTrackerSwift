import SwiftUI
import SwiftData
import Charts

struct MeasurementHistoryView: View {
    @Environment(\.modelContext) private var context

    let kind: MeasurementKind

    @Query private var settingsList: [Settings]
    private var prefersPounds: Bool { settingsList.first?.prefersPounds ?? false }
    private var prefersInches: Bool { false }

    @State private var rangeMonths: Int = 12
    @State private var showAdd = false   // ← presentaremos el formulario en hoja

    private var predicate: Predicate<BodyMeasurement> {
        #Predicate { $0.kindRaw == kind.rawValue }
    }

    @Query(sort: [SortDescriptor(\BodyMeasurement.date, order: .reverse)]) private var all: [BodyMeasurement]
    

    init(kind: MeasurementKind) {
        self.kind = kind
        let pred: Predicate<BodyMeasurement> = #Predicate { $0.kindRaw == kind.rawValue }
        _all = Query(filter: pred, sort: [SortDescriptor(\BodyMeasurement.date, order: .reverse)])
    }

    var body: some View {
        List {
            if !all.isEmpty {
                Section("Trend") {
                    Chart(all) {
                        LineMark(
                            x: .value("Date", $0.date),
                            y: .value("Value", yValue($0))
                        )
                        PointMark(
                            x: .value("Date", $0.date),
                            y: .value("Value", yValue($0))
                        )
                    }
                    .frame(height: 220)
                    .chartYAxisLabel(kind.isLength ? (prefersInches ? "in" : "cm")
                                                  : (prefersPounds ? "lb" : "kg"))
                }
            }

            Section("Entries") {
                ForEach(all) { m in
                    HStack {
                        Text(m.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(display(m))
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(kind.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        // 👇 Presentación en hoja: evita los cuelgues del NavigationLink en toolbar
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddMeasurementView(initialKind: kind)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func yValue(_ m: BodyMeasurement) -> Double {
        if kind.isLength {
            return prefersInches ? (m.value / 2.54) : m.value
        } else {
            return prefersPounds ? (m.value * 2.20462) : m.value
        }
    }

    private func display(_ m: BodyMeasurement) -> String {
        if kind.isLength {
            return MeasurementFormatters.formatLength(cm: m.value, prefersInches: prefersInches)
        } else {
            return MeasurementFormatters.formatWeight(kg: m.value, prefersPounds: prefersPounds)
        }
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(all[idx])
        }
        try? context.save()
    }
}
