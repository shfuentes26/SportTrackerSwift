//
//  ExerciseTypes.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//
import Foundation

public enum ExerciseCategory: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case core = "Core"
    case chestBack = "Chest/Back"   // 👈 una sola categoría
    case arms = "Arms"
    case legs = "Legs"
    public var id: String { rawValue }
}

public struct ExerciseItem: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var category: ExerciseCategory
    public var usesVariableWeight: Bool = false
    public var notes: String = ""
    public var imageBase64: String? = nil
}

