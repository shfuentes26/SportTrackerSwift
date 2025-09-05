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
        let localCfg = ModelConfiguration("LocalOnly", schema: localSchema, isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: localSchema, configurations: localCfg)
        self.appContainer = container

        // --- seed & dedupe (idéntico a lo que tenías) ---
        let cx = container.mainContext

        func seedBasicsIfEmpty(_ context: ModelContext) throws {
            if try context.fetch(FetchDescriptor<Settings>()).isEmpty { context.insert(Settings()) }
            if try context.fetch(FetchDescriptor<UserProfile>()).isEmpty {
                context.insert(UserProfile(displayName: "User", unitSystem: .metric))
            }
            if try context.fetch(FetchDescriptor<Exercise>()).isEmpty {
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
            }
        }
        func dedupeSingletons(_ context: ModelContext) throws {
            func dedupe<T: PersistentModel>(_ t: T.Type) throws {
                var all = try context.fetch(FetchDescriptor<T>())
                guard all.count > 1 else { return }
                all.sort {
                    let u0 = ($0 as AnyObject).value(forKey: "updatedAt") as? Date ?? .distantPast
                    let u1 = ($1 as AnyObject).value(forKey: "updatedAt") as? Date ?? .distantPast
                    return u0 > u1
                }
                for x in all.dropFirst() { context.delete(x) }
            }
            try dedupe(Settings.self); try dedupe(UserProfile.self)
        }
        try seedBasicsIfEmpty(cx); try dedupeSingletons(cx); try cx.save()

        // --- iCloud vía CKRecord (no mirroring de SwiftData) ---
        #if os(iOS) && CLOUD_SYNC
        if UserDefaults.standard.bool(forKey: "useICloudSync") {
            Task { await CKSyncManager.shared.start(using: container) }
        }
        #endif

        return container
    }
}
