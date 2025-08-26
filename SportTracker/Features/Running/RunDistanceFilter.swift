// RunDistanceFilter.swift

// No hace falta importar SwiftUI si solo queda el enum

enum RunDistanceFilter: String, CaseIterable, Identifiable {
    case all, k1, k3, k5, k10, half, marathon
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .k1: return "1K"
        case .k3: return "3K"
        case .k5: return "5K"
        case .k10: return "10K"
        case .half: return "Half"
        case .marathon: return "Marathon"
        }
    }

    /// Distancia mínima en Km (nil = All)
    var minKm: Double? {
        switch self {
        case .all:      return nil
        case .k1:       return 1
        case .k3:       return 3
        case .k5:       return 5
        case .k10:      return 10
        case .half:     return 21.0975
        case .marathon: return 42.195
        }
    }

    func allows(distanceMeters: Double) -> Bool {
        guard let mk = minKm else { return true }
        return distanceMeters / 1000.0 >= mk
    }
}
