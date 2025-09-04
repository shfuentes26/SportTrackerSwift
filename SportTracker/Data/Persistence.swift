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
        // 1) Lista EXACTA de tus modelos (en el mismo orden)
        let all: [any PersistentModel.Type] = [
            //UserProfile.self,
            STUserProfile.self,
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
        ]

        // 2) Comprobación incremental en MEMORIA (aísla de disco/permiso)
        let diagCfg = ModelConfiguration(isStoredInMemoryOnly: true)
        for i in 1...all.count {
            let partial = Schema(Array(all.prefix(i)))
            do {
                _ = try ModelContainer(for: partial, configurations: diagCfg)
                // print opcional:
                print("✅ OK hasta:", all.prefix(i).map { String(describing: $0) }.joined(separator: ", "))
            } catch {
                let failing = String(describing: all[i-1])
                fatalError("❌ Falla al añadir \(failing): \(error)")
            }
        }

        // 3) Si todo pasó, crea el contenedor REAL (igual que antes)
        let schema = Schema(all)
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: schema, configurations: config)

        // 4) Seeding como ya tenías
        let context = container.mainContext
        if try context.fetch(FetchDescriptor<Settings>()).isEmpty {
            context.insert(Settings())
        }
        if try context.fetch(FetchDescriptor<STUserProfile>()).isEmpty {
            context.insert(STUserProfile())
        }
        do {
            let existing = try Set(context.fetch(FetchDescriptor<Exercise>()).map { $0.name.lowercased() })
            let defaults: [Exercise] = [
                // … (deja tu lista tal cual)
            ]
            for ex in defaults where !existing.contains(ex.name.lowercased()) { context.insert(ex) }
        } catch {
            print("Seed exercises error:", error)
        }

        try context.save()
        self.appContainer = container
        return container
    }

}
