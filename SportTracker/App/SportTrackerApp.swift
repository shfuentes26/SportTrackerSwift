//
//  SportTrackerApp.swift
//  SportTracker
//
//  Updated to inject SwiftData container
//

import SwiftUI
import SwiftData
import WatchConnectivity

@main
struct SportTrackerApp: App {
    @UIApplicationDelegateAdaptor(OrientationLockDelegate.self) var appDelegate
    @State private var container: ModelContainer?
    @ObservedObject private var phone = PhoneSession.shared

    init() {
        
        
        let brand = UIColor(named: "BrandGreen") ?? UIColor(red: 0.63, green: 0.913, blue: 0.333, alpha: 1)
        // NAV BAR
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = brand
        nav.titleTextAttributes = [.foregroundColor: UIColor.black]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.black]

        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav   // <- títulos grandes
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = .white     
        do {
            _container = State(initialValue: try Persistence.shared.makeModelContainer())
        } catch {
            assertionFailure("Failed to create ModelContainer: \(error)")
        }
        // 🔑 Inicializa la sesión WatchConnectivity
        _ = PhoneSession.shared
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                ContentView()
                //WorkoutInboxView()
            }
        }
        .modelContainer({
            guard let c = container else { fatalError("[SwiftData] container == nil") }
            return c
        }())
    }
}
