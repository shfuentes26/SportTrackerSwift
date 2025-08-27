//
//  LiveWorkoutSummary.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
import Foundation

struct WorkoutSummary: Identifiable, Equatable {
    let id = UUID()
    let start: Date
    let end: Date
    let distanceKm: Double
    let avgHR: Int
}

