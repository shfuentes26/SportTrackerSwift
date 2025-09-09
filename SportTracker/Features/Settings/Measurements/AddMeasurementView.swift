import SwiftUI
import SwiftData

struct AddMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var settingsList: [Settings]
    private var prefersPounds: Bool { settingsList.first?.prefersPounds ?? false }
    private var prefersInches: Bool { false } // añade toggle si lo deseas

    // Permite abrir el form con un tipo preseleccionado (desde el detalle)
    let initialKind: MeasurementKind?

    @State private var date = Date()
    @State private var kind: MeasurementKind = .waist
    @State private var valueText = ""
    @State private var note = ""
    @State private var error: String?    // <- mantiene el nombre, pero evitamos colisión en catch

    init(initialKind: MeasurementKind? = nil) {
        self.initialKind = initialKind
        _kind = State(initialValue: initialKind ?? .waist)
    }

    var body: some View {
        Form {
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])

            Picker("Type", selection: $kind) {
                ForEach(MeasurementKind.allCases) { k in
                    Text(k.displayName).tag(k)
                }
            }

            HStack {
                TextField(kind.isLength ? "Value (\(prefersInches ? "in" : "cm"))"
                                        : "Value (\(prefersPounds ? "lb" : "kg"))",
                          text: $valueText)
                    .keyboardType(.decimalPad)
                Text(kind.isLength ? (prefersInches ? "in" : "cm")
                                   : (prefersPounds ? "lb" : "kg"))
                    .foregroundStyle(.secondary)
            }

            Section("Notes (optional)") {
                TextField("...", text: $note, axis: .vertical)
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button {
                save()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Add Measurement")
    }

    private func save() {
        let normalized: Double?
        if kind.isLength {
            normalized = MeasurementFormatters.parseLength(valueText, prefersInches: prefersInches)
        } else {
            normalized = MeasurementFormatters.parseWeight(valueText, prefersPounds: prefersPounds)
        }
        guard let value = normalized, value > 0 else {
            error = "Please enter a valid value."
            return
        }

        context.insert(BodyMeasurement(date: date,
                                       kind: kind,
                                       value: value,
                                       note: note.isEmpty ? nil : note))

        do {
            try context.save()
            dismiss()
        } catch let e {                // <- usa otro nombre
            self.error = e.localizedDescription
        }
    }
}
