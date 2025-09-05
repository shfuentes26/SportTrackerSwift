//
//  CKSyncManager.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/5/25.
//
import Foundation
import CloudKit
import SwiftData

@MainActor
final class CKSyncManager {
    static let shared = CKSyncManager()

    private var container: ModelContainer!
    private var ctx: ModelContext { container.mainContext }
    private let db = CKContainer.default().privateCloudDatabase

    private let zoneID = CKRecordZone.ID(zoneName: "SportTrackerZone", ownerName: CKCurrentUserDefaultName)

    private init() {}

    func start(using container: ModelContainer) async {
        self.container = container
        await ensureZone()
        await pushLocalToCloud()
        await pullCloudToLocal()

        // Bucle muy simple; puedes cambiar a notificaciones o background tasks
        Task.detached { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self.pushLocalToCloud()
                await self.pullCloudToLocal()
            }
        }
    }

    // MARK: - Setup
    private func ensureZone() async {
        do {
            try await db.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        } catch { /* si ya existe, ignora */ }
    }

    // MARK: - Push (Local -> Cloud)
    func pushLocalToCloud() async {
        // SETTINGS (uno)
        if let s = ((try? ctx.fetch(FetchDescriptor<Settings>())) ?? []).first {
            await upsert("Settings", id: "settings-singleton") { rec in
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

        // USER PROFILE (uno)
        if let u = ((try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []).first {
            await upsert("UserProfile", id: u.id.uuidString) { rec in
                rec["displayName"] = u.displayName as CKRecordValue?
                rec["unitSystem"] = (u.unitSystem == .imperial ? "imperial" : "metric") as CKRecordValue
                rec["updatedAt"] = u.updatedAt as CKRecordValue
            }
        }

        // GOALS
        if let g = ((try? ctx.fetch(FetchDescriptor<RunningGoal>())) ?? []).first {
            await upsert("RunningGoal", id: g.id.uuidString) { rec in
                rec["weeklyKilometers"] = g.weeklyKilometers as CKRecordValue
                rec["updatedAt"] = g.updatedAt as CKRecordValue
            }
        }
        if let g = ((try? ctx.fetch(FetchDescriptor<GymGoal>())) ?? []).first {
            await upsert("GymGoal", id: g.id.uuidString) { rec in
                rec["targetChestBack"] = g.targetChestBack as CKRecordValue
                rec["targetArms"] = g.targetArms as CKRecordValue
                rec["targetLegs"] = g.targetLegs as CKRecordValue
                rec["targetCore"] = g.targetCore as CKRecordValue
                rec["updatedAt"] = g.updatedAt as CKRecordValue
            }
        }

        // (Opcional) sesiones de running “lite”
        // let sessions = (try? ctx.fetch(FetchDescriptor<RunningSession>())) ?? []
        // for s in sessions {
        //     await upsert("RunningSessionLite", id: s.id.uuidString) { rec in
        //         rec["date"] = s.date as CKRecordValue
        //         rec["durationSeconds"] = s.durationSeconds as CKRecordValue
        //         rec["distanceMeters"] = s.distanceMeters as CKRecordValue
        //         rec["notes"] = s.notes as CKRecordValue?
        //         rec["updatedAt"] = s.updatedAt as CKRecordValue
        //     }
        // }
    }

    // MARK: - Pull (Cloud -> Local)
    func pullCloudToLocal() async {
        // SETTINGS
        if let rec = await fetchOne("Settings", id: "settings-singleton"),
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

        // USER PROFILE
        if let u = ((try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []).first,
           let rec = await fetchOne("UserProfile", id: u.id.uuidString),
           let cloudDate = rec["updatedAt"] as? Date,
           u.updatedAt < cloudDate {
            u.displayName = rec["displayName"] as? String
            let unit = (rec["unitSystem"] as? String) == "imperial" ? UnitSystem.imperial : UnitSystem.metric
            u.unitSystem = unit
            u.updatedAt = cloudDate
            try? ctx.save()
        }

        // GOALS
        if let g = ((try? ctx.fetch(FetchDescriptor<RunningGoal>())) ?? []).first,
           let rec = await fetchOne("RunningGoal", id: g.id.uuidString),
           let cloudDate = rec["updatedAt"] as? Date,
           g.updatedAt < cloudDate {
            g.weeklyKilometers = rec["weeklyKilometers"] as? Double ?? g.weeklyKilometers
            g.updatedAt = cloudDate
            try? ctx.save()
        }
        if let g = ((try? ctx.fetch(FetchDescriptor<GymGoal>())) ?? []).first,
           let rec = await fetchOne("GymGoal", id: g.id.uuidString),
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

    // MARK: - Helpers CK
    private func recordID(_ type: String, id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(type)_\(id)", zoneID: zoneID)
    }

    private func fetchOne(_ type: String, id: String) async -> CKRecord? {
        let rid = recordID(type, id: id)
        return await withCheckedContinuation { cont in
            db.fetch(withRecordID: rid) { rec, _ in cont.resume(returning: rec) }
        }
    }

    private func upsert(_ type: String, id: String, fill: (CKRecord) -> Void) async {
        let rid = recordID(type, id: id)
        let rec = (await fetchOne(type, id: id)) ?? CKRecord(recordType: type, recordID: rid)
        fill(rec)
        await withCheckedContinuation { cont in
            db.save(rec) { _, _ in cont.resume() }
        }
    }
}

