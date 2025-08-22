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
    @State private var showSaved = false
    @State private var navigateToSummaryAfterDismiss = false

    var body: some View {
        VStack(spacing: 16) {
            // Métricas principales
            // Métricas principales (centradas verticalmente)
            Spacer(minLength: 0)

            VStack(spacing: 26) {
                metric(title: "Distance", value: manager.distanceFormatted)
                metric(title: "Time", value: formatElapsed(manager.elapsed))
                metric(title: "Pace", value: manager.paceFormatted)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 0)
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
                    manager.end { workout in
                            saveToAppModel(workout: workout)
                            showSaved = true
                        }
                } label: {
                    controlLabel("Finish", systemImage: "stop.fill")
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Live Run")
        .brandHeaderSpacer()
        .alert("Workout saved", isPresented: $showSaved) {
            Button("OK") {
                navigateToSummaryAfterDismiss = true   // 1) marcar
                dismiss()                               // 2) cerrar primero
            }
        } message: {
            Text("Your run has been saved.")
        }.onDisappear {                       // ⬅️ AÑADE ESTO AQUÍ
            if navigateToSummaryAfterDismiss {
                NotificationCenter.default.post(name: .navigateToSummary, object: nil)
                navigateToSummaryAfterDismiss = false
            }
        }
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
        VStack(spacing: 6) {
            Text(title)                          // ← primero el literal
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)                           // ← luego el valor
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
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
    private func saveToAppModel(workout: HKWorkout?) {
        // Métricas del manager
        let distance = manager.distanceMeters
        let duration = Int(manager.elapsed.rounded())
        let date = Date()

        // Crea la sesión de carrera (puedes añadir notes o polyline si las tienes)
        let session = RunningSession(
            date: date,
            durationSeconds: duration,
            distanceMeters: distance,
            notes: nil,
            routePolyline: manager.exportedPolyline() 
        )

        // Puntuación usando Settings (distancia + tiempo + bonus por ritmo vs baseline)
        session.totalPoints = computeRunningPoints(
            distanceMeters: distance,
            durationSeconds: duration
        )

        // Guarda el UUID del workout de Health como referencia (opcional)
        if let workout = workout {
            session.remoteId = workout.uuid.uuidString
        }

        // Inserta y persiste
        context.insert(session)
        do {
            try context.save()
        } catch {
            print("Error saving RunningSession:", error)
        }
    }
    
    // MARK: - Scoring
    /// Calcula puntos según tus Settings:
    /// - distancePts = km * runningDistanceFactor
    /// - timePts     = (min) * runningTimeFactor
    /// - paceBonus   = max(0, (baseline - pace)/baseline) * runningPaceFactor
    private func computeRunningPoints(distanceMeters: Double, durationSeconds: Int) -> Double {
        // Intenta leer Settings; si no hay, usa los defaults del modelo (sin persistirlos)
        let settings: Settings = (try? context.fetch(FetchDescriptor<Settings>()).first) ?? Settings()

        let km = distanceMeters / 1000.0
        let minutes = Double(durationSeconds) / 60.0
        let paceSecPerKm = durationSeconds > 0 && km > 0 ? Double(durationSeconds) / km : settings.runningPaceBaselineSecPerKm

        let distancePts = km * settings.runningDistanceFactor
        let timePts = minutes * settings.runningTimeFactor
        let paceBonus = max(0, (settings.runningPaceBaselineSecPerKm - paceSecPerKm) / settings.runningPaceBaselineSecPerKm) * settings.runningPaceFactor

        return distancePts + timePts + paceBonus
    }
}

