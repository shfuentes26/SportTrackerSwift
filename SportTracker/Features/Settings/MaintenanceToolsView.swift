//
//  MaintenanceToolsView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/26/25.
//
import SwiftUI
import SwiftData
import HealthKit

struct MaintenanceToolsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage("didRunRoutesBackfillOnce") private var didRunOnce = false
    @State private var isRunning = false
    @State private var summary: String?

    var body: some View {
        List {
            if !didRunOnce {
                Section("One-time fixes") {
                    Button {
                        Task { await runBackfill() }
                    } label: {
                        Label("Backfill missing routes from Apple Health", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isRunning)

                    if isRunning {
                        ProgressView("Working…")
                    }
                }
            }

            if let s = summary {
                Section("Result") {
                    Text(s).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Maintenance")
    }

    private func runBackfill() async {
        isRunning = true
        defer { isRunning = false }

        do {
            // Asegura permisos (tu manager ya declara workoutRoute en readTypes)
            try await HealthKitManager.shared.requestAuthorization()

            let res = try await HealthKitImportService.backfillMissingRoutes(context: context)
            summary = "Updated \(res.updated) of \(res.scanned) runs. Not found in HK: \(res.notFoundInHK). No route in HK: \(res.noRouteInHK)."
            didRunOnce = true   // 🔒 oculta el botón a partir de ahora
        } catch {
            summary = "Error: \(error.localizedDescription)"
        }
    }
}

