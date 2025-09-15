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
    
    private(set) var appContainer: ModelContainer?

    @MainActor
    func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            Settings.self,
            Exercise.self,
            StrengthSet.self,
            StrengthSession.self,
            RunningSession.self,
            RunningGoal.self,
            GymGoal.self,
            RunningWatchDetail.self,
            WatchHRPoint.self,
            WatchPacePoint.self,
            WatchElevationPoint.self,
            RunningWatchSplit.self,
            BodyMeasurement.self
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
        // Seed / completar ejercicios recomendados (por nombre, sin duplicar)
        do {
            let existing = try Set(context.fetch(FetchDescriptor<Exercise>()).map { $0.name.lowercased() })

            let defaults: [Exercise] = [
                // ===== Chest / Back =====
                Exercise(name: "Bench Press", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Barbell bench press", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Machine Fly", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Pec deck fly", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Push Ups", muscleGroup: .chestBack, isWeighted: false,
                         exerciseDescription: "Bodyweight push-up", iconSystemName: "figure.strengthtraining.functional", isCustom: false),

                // Back extra solicitados
                Exercise(name: "Lat Pulldown", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Cable pulldown", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Pull-ups", muscleGroup: .chestBack, isWeighted: false,
                         exerciseDescription: "Bodyweight", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Assisted Pull-ups", muscleGroup: .chestBack, isWeighted: false,
                         exerciseDescription: "Machine assisted", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Shoulder Shrug", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Bodyweight", iconSystemName: "figure.strengthtraining.functional", isCustom: false),

                // ===== Arms =====
                Exercise(name: "Dumbbell Curl", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Biceps curl", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Pushdown (Bar)", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Triceps cable pushdown", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Side Lateral Raise", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Dumbbell lateral raise", iconSystemName: "dumbbell", isCustom: false),
                // Recomendados extra
                Exercise(name: "Hammer Curl", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Neutral grip curl", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Overhead Triceps Extension", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "DB/rope overhead extension", iconSystemName: "dumbbell", isCustom: false),

                // ===== Legs =====
                Exercise(name: "Squat", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Back/front squat", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Lunge", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "DB/barbell lunges", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Deadlift", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Conventional/sumo", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Leg Extension", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Machine leg extension", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Calf Raises", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Standing/seated", iconSystemName: "dumbbell", isCustom: false),
                // Recomendados extra
                Exercise(name: "Romanian Deadlift", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Hip hinge (RDL)", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Leg Press", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Machine leg press", iconSystemName: "dumbbell", isCustom: false),

                // ===== Core (recomendados) =====
                Exercise(name: "Plank", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Isometric hold", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Crunches", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Floor crunch", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Hanging Leg Raise", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Bar hang leg raise", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Russian Twist", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Floor/medicine ball", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
            ]

            for ex in defaults {
                if !existing.contains(ex.name.lowercased()) {
                    context.insert(ex)
                }
            }
        } catch {
            print("Seed exercises error:", error)
        }

        try context.save()
        self.appContainer = container
        return container
    }
}
