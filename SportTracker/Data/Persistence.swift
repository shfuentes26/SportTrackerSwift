//
//  Persistence.swift
//  SportTracker
//
//  SwiftData container + seeding on first launch (igual que MAIN)
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
        // Esquema con ambos perfiles para compatibilidad y migración
        let schema = Schema([
            UserProfile.self,          // ← nuevo: compatible con MAIN
            STUserProfile.self,        // ← existente en CLOUD
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
            RunningWatchSplit.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = container.mainContext

        // ---- 0) Deduplicar Settings (singleton) ----
        do {
            var all = try context.fetch(FetchDescriptor<Settings>())
            if all.isEmpty {
                context.insert(Settings())
            } else if all.count > 1 {
                // Conserva el Settings más reciente
                all.sort { ($0.updatedAt) > ($1.updatedAt) }
                let keep = all.removeFirst()
                for s in all { context.delete(s) }
                // normaliza timestamps
                keep.updatedAt = Date()
            }
        } catch {
            print("Settings dedupe error:", error)
        }

        // ---- 1) Consolidar UserProfile (canónico) ----
        do {
            let cloudProfiles  = try context.fetch(FetchDescriptor<STUserProfile>())
            let localProfiles  = try context.fetch(FetchDescriptor<UserProfile>())
            let totalCount     = cloudProfiles.count + localProfiles.count

            func makeFromST(_ src: STUserProfile) -> UserProfile {
                let dst = UserProfile()
                dst.createdAt     = src.createdAt
                dst.updatedAt     = Date()
                dst.displayName   = src.displayName
                dst.unitSystemRaw = src.unitSystemRaw
                dst.syncStateRaw  = src.syncStateRaw
                return dst
            }

            switch (localProfiles.isEmpty, cloudProfiles.isEmpty) {
            case (true, true):
                // No hay perfiles en ninguna entidad → crea UNO solo en UserProfile
                context.insert(UserProfile())
            case (false, _):
                // Ya existe UserProfile → eliminas duplicados extra (UserProfile y STUserProfile)
                // 1) Dedup dentro de UserProfile (deja 1)
                var locals = localProfiles.sorted { $0.updatedAt > $1.updatedAt }
                let keep = locals.removeFirst()
                for p in locals { context.delete(p) }

                // 2) Borra todos los STUserProfile (se unifica en la clase canónica)
                for p in cloudProfiles { context.delete(p) }

                // normaliza timestamps
                keep.updatedAt = Date()

            case (true, false):
                // No hay UserProfile pero sí STUserProfile → migra el más reciente a UserProfile y borra STs
                let src = cloudProfiles.sorted { $0.updatedAt > $1.updatedAt }.first!
                let migrated = makeFromST(src)
                context.insert(migrated)
                for p in cloudProfiles { context.delete(p) }
            }
        } catch {
            print("UserProfile consolidation error:", error)
        }

        // ---- 2) Seed de ejercicios SIN duplicar (como ya tenías) ----
        do {
            let existing = try Set(
                context.fetch(FetchDescriptor<Exercise>()).map { $0.name.lowercased() }
            )

            let defaults: [Exercise] = [
                // (lista igual que en tu versión actual)
                Exercise(name: "Bench Press", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Barbell bench press", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Machine Fly", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Pec deck fly", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Push Ups", muscleGroup: .chestBack, isWeighted: false,
                         exerciseDescription: "Bodyweight push-up", iconSystemName: "figure.strengthtraining.functional", isCustom: false),

                Exercise(name: "Lat Pulldown", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Cable pulldown", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Pull-ups", muscleGroup: .chestBack, isWeighted: false,
                         exerciseDescription: "Bodyweight", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Assisted Pull-ups", muscleGroup: .chestBack, isWeighted: false,
                         exerciseDescription: "Machine assisted", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Schouder Shrug", muscleGroup: .chestBack, isWeighted: true,
                         exerciseDescription: "Bodyweight", iconSystemName: "figure.strengthtraining.functional", isCustom: false),

                Exercise(name: "Dumbbell Curl", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Biceps curl", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Pushdown (Bar)", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Triceps cable pushdown", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Side Lateral Raise", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Dumbbell lateral raise", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Hammer Curl", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "Neutral grip curl", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Overhead Triceps Extension", muscleGroup: .arms, isWeighted: true,
                         exerciseDescription: "DB/rope overhead extension", iconSystemName: "dumbbell", isCustom: false),

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
                Exercise(name: "Romanian Deadlift", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Hip hinge (RDL)", iconSystemName: "dumbbell", isCustom: false),
                Exercise(name: "Leg Press", muscleGroup: .legs, isWeighted: true,
                         exerciseDescription: "Machine leg press", iconSystemName: "dumbbell", isCustom: false),

                Exercise(name: "Plank", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Isometric hold", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Crunches", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Floor crunch", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Hanging Leg Raise", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Bar hang leg raise", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                Exercise(name: "Russian Twist", muscleGroup: .core, isWeighted: false,
                         exerciseDescription: "Floor/medicine ball", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
            ]

            for ex in defaults where !existing.contains(ex.name.lowercased()) {
                context.insert(ex)
            }
        } catch {
            print("Seed exercises error:", error)
        }

        try context.save()
        self.appContainer = container
        return container
    }
}
