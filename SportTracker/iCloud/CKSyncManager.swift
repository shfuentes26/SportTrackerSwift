import Foundation
import CloudKit
import SwiftData

@MainActor
final class CKSyncManager {
    static let shared = CKSyncManager()
    private init() {}

    // MARK: - Infra
    private var container: ModelContainer!
    private var ctx: ModelContext { container.mainContext }
    private let db = CKContainer.default().privateCloudDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "SportTrackerZone", ownerName: CKCurrentUserDefaultName)

    // Control de encendido y bucle
    private var loopTask: Task<Void, Never>?
    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: "useICloudSync") }

    // Record types
    private enum RT {
        static let settings = "Settings"
        static let user     = "UserProfile"
        static let rGoal    = "RunningGoal"
        static let gGoal    = "GymGoal"
        static let run      = "Run"
        static let gym      = "Gym"
        static let gymSet   = "GymSet"
        static let exercise = "Exercise"
    }

    // Snapshots para detectar borrados locales (solo trainings)
    private let lastRunIDsKey = "cksync.lastRunIDs"
    private let lastGymIDsKey = "cksync.lastGymIDs"

    // MARK: - Normalización de nombres
    private func slug(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
         .trimmingCharacters(in: .whitespacesAndNewlines)
         .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
         .lowercased()
    }

    // MARK: - API
    func start(using container: ModelContainer) async {
        self.container = container
        if !isEnabled {
                print("[iCloud] Sync is OFF → CKSyncManager not started")
                return
        }
        // Si el switch está OFF, no arrancamos nada
        guard isEnabled else { return }

        await ensureZone()
        await syncOnce()

        // Bucle periódico controlado por el switch
        loopTask?.cancel()
        loopTask = Task.detached { [weak self] in
            while let self, !Task.isCancelled {
                if await !self.isEnabled {
                    try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                    continue
                }
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                await self.syncOnce()
            }
        }
    }

    private func syncOnce() async {
        guard isEnabled, container != nil else { return }

        await pushSettingsUserGoals()
        await pushRuns()
        await pushGymsAndSets()

        await pullSettingsUserGoalsAndMerge()
        await pullRunsAndMerge()
        await pullGymsAndSetsAndMerge()

        await propagateLocalDeletions()
        await snapshotLocalTrainingIDs()
    }

    // MARK: - Zone
    private func ensureZone() async {
        do { try await db.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: []) }
        catch { /* ya existe */ }
    }

    // MARK: - Helpers IDs
    private func rid(_ type: String, _ key: String) -> CKRecord.ID { CKRecord.ID(recordName: "\(type)_\(key)", zoneID: zoneID) }
    private func recNameRun(_ id: UUID) -> String { "run:\(id.uuidString)" }
    private func recNameGym(_ id: UUID) -> String { "gym:\(id.uuidString)" }
    private func recNameSet(gymID: UUID, setID: UUID) -> String { "gymset:\(gymID.uuidString):\(setID.uuidString)" }
    private func recNameExercise(_ name: String) -> String { "ex:\(slug(name))" }

    // MARK: - CloudKit util
    private func fetchOne(_ type: String, name: String) async -> CKRecord? {
        await withCheckedContinuation { cont in
            db.fetch(withRecordID: rid(type, name)) { rec, _ in cont.resume(returning: rec) }
        }
    }
    private func upsert(_ type: String, name: String, fill: (CKRecord) -> Void) async {
        let rec = (await fetchOne(type, name: name)) ?? CKRecord(recordType: type, recordID: rid(type, name))
        fill(rec)
        await withCheckedContinuation { cont in db.save(rec) { _, _ in cont.resume() } }
    }
    private func queryAll(_ type: String) async -> [CKRecord] {
        await withCheckedContinuation { cont in
            let q = CKQuery(recordType: type, predicate: NSPredicate(value: true))
            let op = CKQueryOperation(query: q)
            var out: [CKRecord] = []
            op.zoneID = zoneID
            op.recordMatchedBlock = { _, result in if case let .success(r) = result { out.append(r) } }
            op.queryResultBlock = { _ in cont.resume(returning: out) }
            db.add(op)
        }
    }
    private func deleteRecords(names: [String], type: String) async {
        guard !names.isEmpty else { return }
        let ids = names.map { rid(type, $0) }
        await withCheckedContinuation { cont in
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
            op.modifyRecordsResultBlock = { _ in cont.resume() }
            db.add(op)
        }
    }

    // MARK: - Push: Settings/User/Goals
    private func pushSettingsUserGoals() async {
        if let s = ((try? ctx.fetch(FetchDescriptor<Settings>())) ?? []).first {
            await upsert(RT.settings, name: "singleton") { rec in
                rec["updatedAt"] = s.updatedAt as CKRecordValue
                rec["runningDistanceFactor"] = s.runningDistanceFactor as CKRecordValue
                rec["runningTimeFactor"] = s.runningTimeFactor as CKRecordValue
                rec["runningPaceBaselineSecPerKm"] = s.runningPaceBaselineSecPerKm as CKRecordValue
                rec["runningPaceFactor"] = s.runningPaceFactor as CKRecordValue
                rec["gymRepsFactor"] = s.gymRepsFactor as CKRecordValue
                rec["gymWeightedFactor"] = s.gymWeightedFactor as CKRecordValue
                rec["prefersMiles"] = s.prefersMiles as CKRecordValue
                rec["prefersPounds"] = s.prefersPounds as CKRecordValue
            }
        }
        if let u = ((try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []).first {
            await upsert(RT.user, name: u.id.uuidString) { rec in
                rec["displayName"] = u.displayName as CKRecordValue?
                rec["unitSystem"] = (u.unitSystem == .imperial ? "imperial" : "metric") as CKRecordValue
                rec["updatedAt"] = u.updatedAt as CKRecordValue
            }
        }
        if let g = ((try? ctx.fetch(FetchDescriptor<RunningGoal>())) ?? []).first {
            await upsert(RT.rGoal, name: g.id.uuidString) { rec in
                rec["weeklyKilometers"] = g.weeklyKilometers as CKRecordValue
                rec["updatedAt"] = g.updatedAt as CKRecordValue
            }
        }
        if let g = ((try? ctx.fetch(FetchDescriptor<GymGoal>())) ?? []).first {
            await upsert(RT.gGoal, name: g.id.uuidString) { rec in
                rec["targetChestBack"] = g.targetChestBack as CKRecordValue
                rec["targetArms"] = g.targetArms as CKRecordValue
                rec["targetLegs"] = g.targetLegs as CKRecordValue
                rec["targetCore"] = g.targetCore as CKRecordValue
                rec["updatedAt"] = g.updatedAt as CKRecordValue
            }
        }
    }

    // MARK: - Push: Runs
    private func pushRuns() async {
        let runs: [RunningSession] = (try? ctx.fetch(FetchDescriptor<RunningSession>())) ?? []
        for r in runs {
            let name = recNameRun(r.id)
            await upsert(RT.run, name: name) { rec in
                rec["date"] = r.date as CKRecordValue
                rec["durationSeconds"] = r.durationSeconds as CKRecordValue
                rec["distanceMeters"] = r.distanceMeters as CKRecordValue
                rec["notes"] = r.notes as CKRecordValue?
                rec["routePolyline"] = r.routePolyline as CKRecordValue?
                rec["totalPoints"] = r.totalPoints as CKRecordValue
                rec["updatedAt"] = r.updatedAt as CKRecordValue
            }
        }
    }

    // MARK: - Push: Gyms & Sets
    private func pushGymsAndSets() async {
        let gyms: [StrengthSession] = (try? ctx.fetch(FetchDescriptor<StrengthSession>())) ?? []
        for g in gyms {
            let gName = recNameGym(g.id)
            await upsert(RT.gym, name: gName) { rec in
                rec["date"] = g.date as CKRecordValue
                rec["durationSeconds"] = (g.durationSeconds ?? 0) as CKRecordValue
                rec["notes"] = g.notes as CKRecordValue?
                rec["totalPoints"] = g.totalPoints as CKRecordValue
                rec["updatedAt"] = g.updatedAt as CKRecordValue
            }

            for s in g.sets {
                let sName = recNameSet(gymID: g.id, setID: s.id)
                let ex = s.exerciseResolved
                await upsert(RT.gymSet, name: sName) { rec in
                    rec["gymRef"] = gName as CKRecordValue
                    rec["order"] = s.order as CKRecordValue
                    rec["reps"] = s.reps as CKRecordValue
                    rec["weightKg"] = (s.weightKg ?? 0) as CKRecordValue
                    rec["restSeconds"] = (s.restSeconds ?? 0) as CKRecordValue
                    rec["exerciseName"] = ex.name as CKRecordValue
                    rec["exerciseWeighted"] = ex.isWeighted as CKRecordValue
                    rec["muscleGroup"] = ex.muscleGroup.rawValue as CKRecordValue
                    rec["updatedAt"] = s.updatedAt as CKRecordValue
                }
            }
        }
    }

    // MARK: - Pull/Merge: Settings/User/Goals (igual que antes)

    private func pullSettingsUserGoalsAndMerge() async {
        // ... (sin cambios funcionales)
        if let rec = await fetchOne(RT.settings, name: "singleton"),
           let s = ((try? ctx.fetch(FetchDescriptor<Settings>())) ?? []).first,
           let cloudDate = rec["updatedAt"] as? Date,
           s.updatedAt < cloudDate {
            s.runningDistanceFactor = rec["runningDistanceFactor"] as? Double ?? s.runningDistanceFactor
            s.runningTimeFactor = rec["runningTimeFactor"] as? Double ?? s.runningTimeFactor
            s.runningPaceBaselineSecPerKm = rec["runningPaceBaselineSecPerKm"] as? Double ?? s.runningPaceBaselineSecPerKm
            s.runningPaceFactor = rec["runningPaceFactor"] as? Double ?? s.runningPaceFactor
            s.gymRepsFactor = rec["gymRepsFactor"] as? Double ?? s.gymRepsFactor
            s.gymWeightedFactor = rec["gymWeightedFactor"] as? Double ?? s.gymWeightedFactor
            s.prefersMiles = rec["prefersMiles"] as? Bool ?? s.prefersMiles
            s.prefersPounds = rec["prefersPounds"] as? Bool ?? s.prefersPounds
            s.updatedAt = cloudDate
            try? ctx.save()
        }

        if let u = ((try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []).first,
           let rec = await fetchOne(RT.user, name: u.id.uuidString),
           let cloudDate = rec["updatedAt"] as? Date,
           u.updatedAt < cloudDate {
            u.displayName = rec["displayName"] as? String
            let unit = (rec["unitSystem"] as? String) == "imperial" ? UnitSystem.imperial : UnitSystem.metric
            u.unitSystem = unit
            u.updatedAt = cloudDate
            try? ctx.save()
        }

        if let g = ((try? ctx.fetch(FetchDescriptor<RunningGoal>())) ?? []).first,
           let rec = await fetchOne(RT.rGoal, name: g.id.uuidString),
           let cloudDate = rec["updatedAt"] as? Date,
           g.updatedAt < cloudDate {
            g.weeklyKilometers = rec["weeklyKilometers"] as? Double ?? g.weeklyKilometers
            g.updatedAt = cloudDate
            try? ctx.save()
        }
        if let g = ((try? ctx.fetch(FetchDescriptor<GymGoal>())) ?? []).first,
           let rec = await fetchOne(RT.gGoal, name: g.id.uuidString),
           let cloudDate = rec["updatedAt"] as? Date,
           g.updatedAt < cloudDate {
            g.targetChestBack = rec["targetChestBack"] as? Int ?? g.targetChestBack
            g.targetArms = rec["targetArms"] as? Int ?? g.targetArms
            g.targetLegs = rec["targetLegs"] as? Int ?? g.targetLegs
            g.targetCore = rec["targetCore"] as? Int ?? g.targetCore
            g.updatedAt = cloudDate
            try? ctx.save()
        }
    }

    // MARK: - Pull/Merge: Runs (igual)

    private func pullRunsAndMerge() async {
        let recs = await queryAll(RT.run)
        let locals: [RunningSession] = (try? ctx.fetch(FetchDescriptor<RunningSession>())) ?? []
        var byID = Dictionary(uniqueKeysWithValues: locals.map { ($0.id, $0) })

        for r in recs {
            guard let name = r.recordID.recordName.split(separator: "_").last,
                  name.hasPrefix("run:"),
                  let uuid = UUID(uuidString: String(name.dropFirst(4))) else { continue }

            let inc = RunningSession(
                id: uuid,
                date: (r["date"] as? Date) ?? Date(),
                durationSeconds: (r["durationSeconds"] as? Int) ?? 0,
                distanceMeters: (r["distanceMeters"] as? Double) ?? 0,
                notes: r["notes"] as? String,
                routePolyline: r["routePolyline"] as? String,
                remoteId: nil
            )
            inc.totalPoints = (r["totalPoints"] as? Double) ?? 0

            if let ex = byID[uuid] {
                ex.date = max(ex.date, inc.date)
                ex.durationSeconds = max(ex.durationSeconds, inc.durationSeconds)
                ex.distanceMeters = max(ex.distanceMeters, inc.distanceMeters)
                if ex.notes == nil { ex.notes = inc.notes }
                if ex.routePolyline == nil { ex.routePolyline = inc.routePolyline }
                ex.totalPoints = max(ex.totalPoints, inc.totalPoints)
            } else {
                ctx.insert(inc)
                byID[uuid] = inc
            }
        }
        try? ctx.save()
    }

    // MARK: - Pull/Merge: Gyms & Sets (normalizado + sin duplicar ejercicios)

    // Idempotent merge: crea a lo sumo 1 Exercise por nombre normalizado (slug)
    private func pullGymsAndSetsAndMerge() async {
        let gymRecs = await queryAll(RT.gym)
        let setRecs = await queryAll(RT.gymSet)

        // Index de sesiones locales por ID
        let locals: [StrengthSession] = (try? ctx.fetch(FetchDescriptor<StrengthSession>())) ?? []
        var gymByID = Dictionary(uniqueKeysWithValues: locals.map { ($0.id, $0) })

        // 🔑 Index de ejercicios por SLUG (nombre normalizado)
        let localExs: [Exercise] = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        var exByName = Dictionary(uniqueKeysWithValues: localExs.map { (slug($0.name), $0) })

        // UPSERT de gym sessions (igual que antes)
        for r in gymRecs {
            guard let tail = r.recordID.recordName.split(separator: "_").last,
                  tail.hasPrefix("gym:"),
                  let uuid = UUID(uuidString: String(tail.dropFirst(4))) else { continue }

            let inc = StrengthSession(
                id: uuid,
                date: (r["date"] as? Date) ?? Date(),
                durationSeconds: r["durationSeconds"] as? Int,
                notes: r["notes"] as? String
            )
            inc.totalPoints = (r["totalPoints"] as? Double) ?? 0

            if let ex = gymByID[uuid] {
                ex.date = max(ex.date, inc.date)
                if ex.durationSeconds == nil { ex.durationSeconds = inc.durationSeconds }
                if ex.notes == nil { ex.notes = inc.notes }
                ex.totalPoints = max(ex.totalPoints, inc.totalPoints)
            } else {
                ctx.insert(inc)
                gymByID[uuid] = inc
            }
        }

        // Agrupa sets por gymRef
        var setsByGymRef: [String: [CKRecord]] = [:]
        for s in setRecs {
            guard let gymRef = s["gymRef"] as? String else { continue }
            setsByGymRef[gymRef, default: []].append(s)
        }

        // Reconstrucción de sets (creación idempotente de Exercise)
        for (gymRef, recs) in setsByGymRef {
            guard gymRef.hasPrefix("gym:"),
                  let uuid = UUID(uuidString: String(gymRef.dropFirst(4))),
                  let session = gymByID[uuid] else { continue }

            let ordered = recs.sorted { ($0["order"] as? Int ?? 0) < ($1["order"] as? Int ?? 0) }

            for sr in ordered {
                let rawName   = (sr["exerciseName"] as? String ?? "")
                let key       = slug(rawName)                       // ← nombre normalizado
                let weighted  = (sr["exerciseWeighted"] as? Bool) ?? false
                let groupRaw  = (sr["muscleGroup"] as? Int) ?? MuscleGroup.arms.rawValue
                let group     = MuscleGroup(rawValue: groupRaw) ?? .arms

                // Reusar si existe; crear UNA vez si falta y cachear en exByName
                let exercise: Exercise = {
                    if let found = exByName[key] {
                        if !found.isWeighted { found.isWeighted = weighted } // merge suave
                        return found
                    } else {
                        let nameToUse = rawName.isEmpty ? "(Unnamed)" : rawName
                        let created = Exercise(
                            name: nameToUse,
                            muscleGroup: group,
                            isWeighted: weighted,
                            exerciseDescription: nil,
                            iconSystemName: nil,
                            imageData: nil,
                            isCustom: true,
                            notes: ""
                        )
                        ctx.insert(created)
                        exByName[key] = created      // 👈 clave: los siguientes sets ya reusan éste
                        return created
                    }
                }()

                let order = sr["order"] as? Int ?? 0
                let reps  = sr["reps"] as? Int ?? 0
                let w     = (sr["weightKg"] as? Double).flatMap { $0 > 0 ? $0 : nil }
                let rest  = (sr["restSeconds"] as? Int).flatMap { $0 > 0 ? $0 : nil }

                // Evita sets duplicados idénticos
                let exists = session.sets.contains {
                    $0.order == order && $0.reps == reps &&
                    $0.weightKg == w && $0.restSeconds == rest &&
                    ($0.exercise?.name == exercise.name)
                }
                if !exists {
                    let newSet = StrengthSet(exercise: exercise, order: order, reps: reps, weightKg: w, restSeconds: rest)
                    newSet.session = session
                    session.sets.append(newSet)
                    ctx.insert(newSet)
                }
            }
        }

        try? ctx.save()
    }


    // MARK: - Borrados remotos según borrados locales (igual)
    private func propagateLocalDeletions() async {
        let nowRunIDs = Set(((try? ctx.fetch(FetchDescriptor<RunningSession>())) ?? []).map { $0.id.uuidString })
        let nowGymIDs = Set(((try? ctx.fetch(FetchDescriptor<StrengthSession>())) ?? []).map { $0.id.uuidString })

        let lastRunIDs = Set(UserDefaults.standard.stringArray(forKey: lastRunIDsKey) ?? [])
        let lastGymIDs = Set(UserDefaults.standard.stringArray(forKey: lastGymIDsKey) ?? [])

        let runsToDelete = lastRunIDs.subtracting(nowRunIDs).map { recNameRun(UUID(uuidString: $0)!) }
        let gymsToDelete = lastGymIDs.subtracting(nowGymIDs).map { recNameGym(UUID(uuidString: $0)!) }

        await deleteRecords(names: runsToDelete, type: RT.run)
        await deleteRecords(names: gymsToDelete, type: RT.gym)

        if !gymsToDelete.isEmpty {
            let allSets = await queryAll(RT.gymSet)
            let setNamesToDelete: [String] = allSets.compactMap { rec in
                guard let gymRef = rec["gymRef"] as? String else { return nil }
                guard gymsToDelete.contains(gymRef) else { return nil }
                return rec.recordID.recordName.components(separatedBy: "_").last
            }
            await deleteRecords(names: setNamesToDelete, type: RT.gymSet)
        }
    }

    private func snapshotLocalTrainingIDs() async {
        let runs: [RunningSession] = (try? ctx.fetch(FetchDescriptor<RunningSession>())) ?? []
        let gyms: [StrengthSession] = (try? ctx.fetch(FetchDescriptor<StrengthSession>())) ?? []
        UserDefaults.standard.set(runs.map { $0.id.uuidString }, forKey: lastRunIDsKey)
        UserDefaults.standard.set(gyms.map { $0.id.uuidString }, forKey: lastGymIDsKey)
    }

    // MARK: - Dedupe por nombre normalizado (mergea sets y borra perdedores)
    private func dedupeExercisesByNormalizedName() {
        let allExercises: [Exercise] = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        guard allExercises.count > 1 else { return }

        var groups: [String: [Exercise]] = [:]
        for e in allExercises { groups[slug(e.name), default: []].append(e) }

        var allSets: [StrengthSet] = (try? ctx.fetch(FetchDescriptor<StrengthSet>())) ?? []

        for (_, g) in groups where g.count > 1 {
            let winner = g.sorted {
                if $0.isCustom != $1.isCustom { return $1.isCustom } // no-custom primero
                return $0.updatedAt > $1.updatedAt
            }.first!

            for loser in g where loser.id != winner.id {
                for s in allSets where s.exercise?.id == loser.id {
                    s.exercise = winner
                }
                if !winner.isWeighted { winner.isWeighted = loser.isWeighted }
                if winner.exerciseDescription == nil { winner.exerciseDescription = loser.exerciseDescription }
                if winner.iconSystemName == nil { winner.iconSystemName = loser.iconSystemName }
                if winner.imageData == nil { winner.imageData = loser.imageData }
                ctx.delete(loser)
            }
        }
    }
}
