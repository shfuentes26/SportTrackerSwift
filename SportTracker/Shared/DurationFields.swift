//
//  DurationFields.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/20/25.
//
import SwiftUI

struct DurationFields: View {
    @Binding var hours: String
    @Binding var minutes: String
    @Binding var seconds: String

    enum Field: Hashable { case hh, mm, ss }
    @FocusState private var focused: Field?

    var body: some View {
        HStack(spacing: 8) {
            timeBox(text: $hours,   placeholder: "hh",  field: .hh, maxLen: 2)
            Text(":").foregroundStyle(.secondary)
            timeBox(text: $minutes, placeholder: "mm",  field: .mm, maxLen: 2)
            Text(":").foregroundStyle(.secondary)
            timeBox(text: $seconds, placeholder: "ss",  field: .ss, maxLen: 2)
        }
        .onAppear { if hours.isEmpty { focused = .hh } }
        .onChange(of: hours)   { _ in advanceIfFull(.hh, maxLen: 2) }
        .onChange(of: minutes) { _ in advanceIfFull(.mm, maxLen: 2) }
        .onChange(of: seconds) { _ in /* último campo: nada */ }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    private func timeBox(text: Binding<String>, placeholder: String, field: Field, maxLen: Int) -> some View {
        TextField(placeholder, text: Binding(
            get: { text.wrappedValue },
            set: { newValue in
                // solo dígitos, máx. longitud
                let filtered = newValue.filter { $0.isNumber }
                text.wrappedValue = String(filtered.prefix(maxLen))
                // clamp para minutos/segundos
                if field != .hh, let v = Int(text.wrappedValue), v > 59 {
                    text.wrappedValue = "59"
                }
            }
        ))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .frame(minWidth: 44) // suficiente para 2 dígitos
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .focused($focused, equals: field)
        .submitLabel(field == .ss ? .done : .next)
        .onSubmit {
            if field == .hh { focused = .mm }
            else if field == .mm { focused = .ss }
            else { focused = nil }
        }
    }

    private func advanceIfFull(_ field: Field, maxLen: Int) {
        switch field {
        case .hh:
            if hours.count >= maxLen { focused = .mm }
        case .mm:
            if minutes.count >= maxLen { focused = .ss }
        case .ss:
            break
        }
    }
}

// Helper para convertir a segundos cuando guardes
extension DurationFields {
    static func totalSeconds(hours: String, minutes: String, seconds: String) -> Int {
        let h = Int(hours) ?? 0
        let m = Int(minutes) ?? 0
        let s = Int(seconds) ?? 0
        return max(0, h*3600 + m*60 + s)
    }
}

