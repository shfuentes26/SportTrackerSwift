//
//  LiveRunView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/21/25.
//
import SwiftUI
import SwiftData
import HealthKit

struct LiveRunView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var manager = RunningLiveManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // Métricas principales
            HStack {
                metric(title: "Distance", value: manager.distanceFormatted)
                Spacer()
                metric(title: "Time", value: formatElapsed(manager.elapsed))
                Spacer()
                metric(title: "Pace", value: manager.paceFormatted)
            }
            .padding(.horizontal)

            if let hr = manager.currentHeartRate {
                Text("HR \(Int(hr)) bpm").font(.headline)
            }

            Spacer()

            // Controles
            HStack(spacing: 12) {
                if manager.isRunning {
                    Button {
                        manager.pause()
                        haptic(.warning)
                    } label: {
                        controlLabel("Pause", systemImage: "pause.fill")
                    }
                } else {
                    Button {
                        manager.resume()
                        haptic(.success)
                    } label: {
                        controlLabel("Resume", systemImage: "play.fill")
                    }
                }

                Button(role: .destructive) {
                    manager.end { _ in
                        saveToAppModel()
                        dismiss()
                    }
                } label: {
                    controlLabel("Finish", systemImage: "stop.fill")
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Live Run")
        .brandHeaderSpacer()
        .task {
            do {
                try await manager.requestAuthorization()
                try manager.start()
            } catch {
                print("Error starting live run:", error)
            }
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack {
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func controlLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.9)))
            .foregroundStyle(.white)
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d:%02d", s/3600, (s%3600)/60, s%60)
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(type)
        #endif
    }

    // TODO: guarda tu sesión en tu modelo (RunningSession) cuando termine
    private func saveToAppModel() {
        // Aquí crearías y guardarías tu RunningSession usando manager.distanceMeters, manager.elapsed, etc.
        // Ejemplo (ajústalo a tu modelo real):
        /*
        let session = RunningSession(
            date: Date(),
            distanceKm: manager.distanceMeters / 1000.0,
            durationSeconds: Int(manager.elapsed),
            paceSecondsPerKm: manager.elapsed / max(manager.distanceMeters/1000.0, 0.001),
            notes: nil
        )
        context.insert(session)
        try? context.save()
        */
    }
}

