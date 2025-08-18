//
//  Persistence.swift
//  SportTracker
//
//  SwiftData container + simple seeding on first launch
//

import Foundation
import SwiftData
import SwiftUI

final class Persistence {
    static let shared = Persistence()
    private init() {}

    @MainActor
    func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            Settings.self,
            Exercise.self,
            StrengthSet.self,
            StrengthSession.self,
            RunningSession.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: schema, configurations: config)

        // Seed default settings & a couple of sample exercises on first run
        let context = container.mainContext
        if try context.fetch(FetchDescriptor<Settings>()).isEmpty {
            let settings = Settings()
            context.insert(settings)
        }
        if try context.fetch(FetchDescriptor<UserProfile>()).isEmpty {
            let me = UserProfile(displayName: "User", unitSystem: .metric)
            context.insert(me)
        }
        if try context.fetch(FetchDescriptor<Exercise>()).isEmpty {
            let pushUps = Exercise(name: "Push Ups", muscleGroup: .chestBack, isWeighted: false, exerciseDescription: "Bodyweight", iconSystemName: "figure.strengthtraining.functional", isCustom: false)
            let squat = Exercise(name: "Squat", muscleGroup: .legs, isWeighted: true, exerciseDescription: "Barbell or dumbbell", iconSystemName: "dumbbell", isCustom: false)
            context.insert(pushUps)
            context.insert(squat)
        }
        try context.save()
        return container
    }
}
