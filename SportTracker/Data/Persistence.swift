import Foundation
import SwiftData

final class Persistence {
    static let shared = Persistence()
    private init() {}

    private(set) var appContainer: ModelContainer?

    @MainActor
    func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        // Modelos reales (todo local)
        let localModels: [any PersistentModel.Type] = [
            UserProfile.self, Settings.self,
            Exercise.self, RunningSession.self,
            StrengthSet.self, StrengthSession.self,
            RunningWatchDetail.self, WatchHRPoint.self, WatchPacePoint.self,
            WatchElevationPoint.self, RunningWatchSplit.self,
            RunningGoal.self, GymGoal.self
        ]
        let localSchema = Schema(localModels)

        let config = ModelConfiguration(schema: localSchema, isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: localSchema, configurations: config)
        self.appContainer = container

        // 🧹 Migración one-shot (ref → exercise) para builds de prueba previas
        let cx = container.mainContext
        try migrateExerciseRefLinkIfNeeded(context: cx)

        // seed/dedupe…
        func seedBasicsIfEmpty(_ context: ModelContext) throws {
            if try context.fetch(FetchDescriptor<Settings>()).isEmpty { context.insert(Settings()) }
            if try context.fetch(FetchDescriptor<UserProfile>()).isEmpty {
                context.insert(UserProfile(displayName: "User", unitSystem: .metric))
            }

            let iCloudOn = UserDefaults.standard.bool(forKey: "useICloudSync")
            let kv = NSUbiquitousKeyValueStore.default
            let seedKey = "catalogSeededV1"

            let shouldSeedCatalog: Bool = {
                if !iCloudOn { return true }
                return kv.bool(forKey: seedKey) == false
            }()

            var exFD = FetchDescriptor<Exercise>(); exFD.fetchLimit = 1
            if try context.fetch(exFD).isEmpty, shouldSeedCatalog {
                let defaults: [Exercise] = [
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
                    Exercise(name: "Shoulder Shrug", muscleGroup: .chestBack, isWeighted: true,
                             exerciseDescription: "DB/Barbell shrug", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Dumbbell Curl", muscleGroup: .arms, isWeighted: true,
                             exerciseDescription: "Biceps curl", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Pushdown (Bar)", muscleGroup: .arms, isWeighted: true,
                             exerciseDescription: "Triceps cable pushdown", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Side Lateral Raise", muscleGroup: .arms, isWeighted: true,
                             exerciseDescription: "Dumbbell lateral raise", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Hammer Curl", muscleGroup: .arms, isWeighted: true,
                             exerciseDescription: "Neutral grip curl", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Overhead Triceps Extension", muscleGroup: .arms, isWeighted: true,
                             exerciseDescription: "DB/Rope overhead extension", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Squat", muscleGroup: .legs, isWeighted: true,
                             exerciseDescription: "Back/Front squat", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Lunge", muscleGroup: .legs, isWeighted: true,
                             exerciseDescription: "DB/Barbell lunges", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Deadlift", muscleGroup: .legs, isWeighted: true,
                             exerciseDescription: "Conventional/Sumo", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Leg Extension", muscleGroup: .legs, isWeighted: true,
                             exerciseDescription: "Machine leg extension", iconSystemName: "dumbbell", isCustom: false),
                    Exercise(name: "Calf Raises", muscleGroup: .legs, isWeighted: true,
                             exerciseDescription: "Standing/Seated", iconSystemName: "dumbbell", isCustom: false),
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
                             exerciseDescription: "Floor/Medicine ball", iconSystemName: "figure.strengthtraining.functional", isCustom: false),
                ]
                for ex in defaults { context.insert(ex) }

                if iCloudOn { kv.set(true, forKey: seedKey); kv.synchronize() }
            }
        }

        func dedupeSingletons(_ context: ModelContext) throws {
            var settings = try context.fetch(FetchDescriptor<Settings>())
            if settings.count > 1 {
                settings.sort { $0.updatedAt > $1.updatedAt }
                for s in settings.dropFirst() { context.delete(s) }
            }
            var users = try context.fetch(FetchDescriptor<UserProfile>())
            if users.count > 1 {
                users.sort { $0.updatedAt > $1.updatedAt }
                for u in users.dropFirst() { context.delete(u) }
            }
        }

        try seedBasicsIfEmpty(cx); try dedupeSingletons(cx); try cx.save()

        #if os(iOS) && CLOUD_SYNC
        if UserDefaults.standard.bool(forKey: "useICloudSync") {
            Task { await CKSyncManager.shared.start(using: container) }
        }
        #endif

        return container
    }
}
