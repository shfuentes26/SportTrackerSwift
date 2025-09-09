//
//  MeasurementFormatters.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/9/25.
//
import Foundation

struct MeasurementFormatters {
    static func formatLength(cm: Double, prefersInches: Bool) -> String {
        if prefersInches {
            let inches = cm / 2.54
            return String(format: "%.1f in", inches)
        } else {
            return String(format: "%.1f cm", cm)
        }
    }

    static func formatWeight(kg: Double, prefersPounds: Bool) -> String {
        if prefersPounds {
            let lb = kg * 2.20462
            return String(format: "%.1f lb", lb)
        } else {
            return String(format: "%.1f kg", kg)
        }
    }

    static func parseLength(_ text: String, prefersInches: Bool) -> Double? {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return prefersInches ? (v * 2.54) : v // → cm
    }

    static func parseWeight(_ text: String, prefersPounds: Bool) -> Double? {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return prefersPounds ? (v / 2.20462) : v // → kg
    }
}

