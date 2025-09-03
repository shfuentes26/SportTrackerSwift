//
//  LiveWorkoutBridge.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
import Foundation

final class LiveWorkoutBridge: ObservableObject {
    static let shared = LiveWorkoutBridge()
    @Published var hr: Int = 0
    @Published var km: Double = 0
    @Published var elapsed: TimeInterval = 0
    @Published var lastSummary: WorkoutSummary?
    @Published var isRunning: Bool = false
}

