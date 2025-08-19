//
//  UnitFormatters.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//

import Foundation

enum UnitFormatters {
    // número con 0–2 decimales
    private static let nf: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    private static func num(_ x: Double) -> String {
        nf.string(from: x as NSNumber) ?? String(format: "%.2f", x)
    }

    // Distancia: entrada en km; salida "X km" o "Y mi"
    static func distance(_ km: Double, useMiles: Bool) -> String {
        let value = useMiles ? (km / 1.60934) : km
        let unit  = useMiles ? "mi" : "km"
        return "\(num(value)) \(unit)"
    }

    // Ritmo: entrada en s/km; salida "m:ss /km" o "/mi"
    static func pace(secondsPerKm: Double, useMiles: Bool) -> String {
        let secsDouble = useMiles ? (secondsPerKm * 1.60934) : secondsPerKm
        let secs = Int(round(secsDouble))
        let mm = secs / 60, ss = secs % 60
        return String(format: "%d:%02d %@", mm, ss, useMiles ? "min/mi" : "min/km")
    }

    // Peso: entrada en kg; salida "kg" o "lb"
    static func weight(_ kg: Double, usePounds: Bool) -> String {
        let value = usePounds ? (kg * 2.20462) : kg
        let unit  = usePounds ? "lb" : "kg"
        return "\(num(value)) \(unit)"
    }

    // Utilidades de conversión para inputs
    static func km(from userDistance: Double, inputIsMiles: Bool) -> Double {
        inputIsMiles ? userDistance * 1.60934 : userDistance
    }
    static func kg(from userWeight: Double, inputIsPounds: Bool) -> Double {
        inputIsPounds ? userWeight / 2.20462 : userWeight
    }
}
