import Foundation
import SwiftData

final class Persistence {
    static let shared = Persistence()
    private init() {}

    private(set) var appContainer: ModelContainer?
    private var didSeedCatalogThisLaunch = false

    // Normaliza: trim + colapsa espacios + minúsculas
    private func slug(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
         .lowercased()
    }

    @MainActor
    func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        print("[Persistence][makeModelContainer] called")
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
        let cx = container.mainContext
        
        

        // Migración one-shot
        let migKey = "didRun_migrateRefLink_v1"
        if !UserDefaults.standard.bool(forKey: migKey) {
            print("[MIG] migrateExerciseRefLinkIfNeeded → START")
            do {
                try migrateExerciseRefLinkIfNeeded(context: cx)
                UserDefaults.standard.set(true, forKey: migKey)
                print("[MIG] migrateExerciseRefLinkIfNeeded → DONE")
            } catch {
                print("[MIG] ERROR:", String(describing: error))
            }
        } else {
            print("[MIG] migrateExerciseRefLinkIfNeeded → SKIPPED")
        }

        // Log rápido
        func log(_ tag: String) {
            let all = (try? cx.fetch(FetchDescriptor<Exercise>())) ?? []
            print("[DB] \(tag) count =", all.count)
            var g: [String:Int] = [:]
            for e in all { g[slug(e.name), default:0] += 1 }
            let dups = g.filter{$0.value>1}
            if !dups.isEmpty {
                print("[DB] \(tag) DUPLICATES →",
                      dups.map{"\($0.key)×\($0.value)"}.joined(separator:", "))
            }
        }

        log("BEFORE seed")
        try seedBasicsIfNeeded(cx)       // settings/profile + catálogo si falta
        try dedupeSingletons(cx)         // Settings/UserProfile únicos
        try dedupeExercisesByNormalizedName(cx) // 🔧 limpia duplicados previos
        log("AFTER seed")
        try cx.save()

        DispatchQueue.main.asyncAfter(deadline: .now()+5) {
            log("AFTER 5s")
        }

        #if os(iOS) && CLOUD_SYNC
        print("[Persistence][this part of the code is enable because of CLOUD_SYNC called")
        let flag = UserDefaults.standard.bool(forKey: "useICloudSync")
        print("[iCloud] useICloudSync =", flag)
        if flag {
            print("[iCloud] CKSyncManager.start() IS BEING CALLED")
            Task { await CKSyncManager.shared.start(using: container) }
        }
        #endif

        return container
    }

    // MARK: - Seed mínimo
    private func seedBasicsIfNeeded(_ context: ModelContext) throws {
        print("[Persistence][seedBasicsIfNeeded] called")
        if try context.fetch(FetchDescriptor<Settings>()).isEmpty {
            context.insert(Settings())
        }
        if try context.fetch(FetchDescriptor<UserProfile>()).isEmpty {
            context.insert(UserProfile(displayName: "User", unitSystem: .metric))
        }
        try seedExerciseCatalogIfNeeded(context)
    }

    /// Inserta el catálogo base **solo si falta** (chequeo por nombre normalizado)
    private func seedExerciseCatalogIfNeeded(_ context: ModelContext) throws {
        print("[Persistence][seedExerciseCatalogIfNeeded] called")
        guard !didSeedCatalogThisLaunch else { return }
        let iCloudOn = UserDefaults.standard.bool(forKey: "useICloudSync")
        let seedKey = "catalogSeededV1"
        let localSeedKey = "catalogSeededV1_local"

        // Catálogo por defecto (23)
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
                     exerciseDescription: "Floor/Medicine ball", iconSystemName: "figure.strengthtraining.functional", isCustom: false)
        ]

        func norm(_ s: String) -> String { slug(s) }
        let localAlreadySeeded = UserDefaults.standard.bool(forKey: localSeedKey)

        var icloudAlreadySeeded = false
        if iCloudOn {
            print("[Persistence][TRACE] ENTRAMOS EN iCloudOn is:", iCloudOn)
            let kv = NSUbiquitousKeyValueStore.default
            icloudAlreadySeeded = kv.bool(forKey: seedKey)
        }

        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingNames = Set(existing.map { norm($0.name) })
        let seedNames = Set(defaults.map { norm($0.name) })
        let catalogSeemsPresent = seedNames.isSubset(of: existingNames)

        print("[Seed][TRACE] localAlreadySeeded is:", localAlreadySeeded)
        print("[Seed][TRACE] icloudAlreadySeeded is:", icloudAlreadySeeded)
        print("[Seed][TRACE] catalogSeemsPresent is:", catalogSeemsPresent)
        
        let shouldSeed = !(localAlreadySeeded || icloudAlreadySeeded || catalogSeemsPresent)
        if shouldSeed {
            for ex in defaults {
                if !existingNames.contains(norm(ex.name)) {
                    print("[Seed][TRACE] Insertando exercise base:", ex.name)
                    context.insert(ex)
                }
            }
            UserDefaults.standard.set(true, forKey: localSeedKey)
            if iCloudOn {
                let kv = NSUbiquitousKeyValueStore.default
                kv.set(true, forKey: seedKey)
                kv.synchronize()
            }
        }
        didSeedCatalogThisLaunch = true
    }

    private func dedupeSingletons(_ context: ModelContext) throws {
        print("[Persistence][dedupeSingletons] called")
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

    /// 🔧 Dedupe por nombre “slug” (fusiona sets y borra perdedores)
    private func dedupeExercisesByNormalizedName(_ context: ModelContext) throws {
        print("[Persistence][dedupeExercisesByNormalizedName] called")
        let allExercises: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        guard allExercises.count > 1 else { return }

        var groups: [String: [Exercise]] = [:]
        for e in allExercises { groups[slug(e.name), default: []].append(e) }

        var allSets: [StrengthSet] = (try? context.fetch(FetchDescriptor<StrengthSet>())) ?? []

        for (_, g) in groups where g.count > 1 {
            // Ganador: no-custom primero; si empate, el más reciente
            let winner = g.sorted {
                if $0.isCustom != $1.isCustom { return $1.isCustom } // false antes que true
                return $0.updatedAt > $1.updatedAt
            }.first!

            for loser in g where loser.id != winner.id {
                // Reasigna sets al ganador
                for s in allSets where s.exercise?.id == loser.id { s.exercise = winner }
                // Conserva info útil
                if !winner.isWeighted { winner.isWeighted = loser.isWeighted }
                if winner.exerciseDescription == nil { winner.exerciseDescription = loser.exerciseDescription }
                if winner.iconSystemName == nil { winner.iconSystemName = loser.iconSystemName }
                if winner.imageData == nil { winner.imageData = loser.imageData }
                context.delete(loser)
            }
        }
    }
}
