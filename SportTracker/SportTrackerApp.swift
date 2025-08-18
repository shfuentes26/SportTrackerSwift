//
//  SportTrackerApp.swift
//  SportTracker
//
//  Updated to inject SwiftData container
//

import SwiftUI
import SwiftData

@main
struct SportTrackerApp: App {
    @State private var container: ModelContainer?

    init() {
        do {
            _container = State(initialValue: try Persistence.shared.makeModelContainer())
        } catch {
            assertionFailure("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container!)
    }
}
