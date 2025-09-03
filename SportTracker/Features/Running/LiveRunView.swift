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

    // NUEVO: control de confirmación y cambios sin guardar
    @State private var showExitConfirm = false
    @State private var hasUnsavedChanges = false

    var body: some View {
        VStack(spacing: 16) {
            // Métricas principales (centradas verticalmente)
            //Spacer(minLength: 0)

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
                        // al guardar ya no hay cambios pendientes
                        hasUnsavedChanges = false
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

        // Ocultar TabBar durante el live
        .modifier(HideTabBar())

        // Desactivar gesto de retroceso si hay cambios sin guardar
        .interactiveDismissDisabled(hasUnsavedChanges)

        // Back personalizado con confirmación
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasUnsavedChanges {
                        showExitConfirm = true
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
        .alert("Leave without saving?", isPresented: $showExitConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Discard changes", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("You have unsaved changes from this Live Run. Are you sure you want to leave?")
        }

        // Alert de guardado + navegación al summary (tu lógica existente)
        .alert("Workout saved", isPresented: $showSaved) {
            Button("OK") {
                navigateToSummaryAfterDismiss = true
                dismiss()
            }
        } message: {
            Text("Your run has been saved.")
        }
        .onDisappear {
            // Restaurar TabBar y, si procede, ir al Summary
            if navigateToSummaryAfterDismiss {
                NotificationCenter.default.post(name: .navigateToSummary, object: nil)
                navigateToSummaryAfterDismiss = false
            }
        }
        .task {
            do {
                try await manager.requestAuthorization()
                try manager.start()
                // Marcamos que hay cambios tan pronto como comienza la sesión
                hasUnsavedChanges = true
            } catch {
                print("Error starting live run:", error)
            }
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
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

    // Guarda tu sesión en tu modelo cuando termine
    private func saveToAppModel(workout: HKWorkout?) {
        let distance = manager.distanceMeters
        let duration = Int(manager.elapsed.rounded())
        let date = Date()

        let session = RunningSession(
            date: date,
            durationSeconds: duration,
            distanceMeters: distance,
            notes: nil,
            routePolyline: manager.exportedPolyline()
        )

        session.totalPoints = computeRunningPoints(
            distanceMeters: distance,
            durationSeconds: duration
        )

        if let workout = workout {
            session.remoteId = workout.uuid.uuidString
        }

        context.insert(session)
        do {
            try context.save()
        } catch {
            print("Error saving RunningSession:", error)
        }
    }

    // MARK: - Scoring
    private func computeRunningPoints(distanceMeters: Double, durationSeconds: Int) -> Double {
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

/// Modifier para ocultar la TabBar mientras esta vista está activa.
private struct HideTabBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(EmptyView().onAppear {
                // iOS 16+: forma nativa
                // (No hace falta nada si usamos .toolbar(.hidden, for: .tabBar))
                #if !os(watchOS)
                if #available(iOS 16.0, *) {
                    // se gestiona con .toolbar(.hidden, for: .tabBar) debajo
                } else {
                    // Fallback iOS 15: ocultar globalmente mientras dura la vista
                    UITabBar.appearance().isHidden = true
                }
                #endif
            }.onDisappear {
                #if !os(watchOS)
                if #available(iOS 16.0, *) {
                    // nada
                } else {
                    UITabBar.appearance().isHidden = false
                }
                #endif
            })
            .applyIfAvailableiOS16 {
                $0.toolbar(.hidden, for: .tabBar)
            }
    }
}

// Helper para aplicar condicional en iOS16+
private extension View {
    @ViewBuilder
    func applyIfAvailableiOS16<T: View>(_ transform: (Self) -> T) -> some View {
        if #available(iOS 16.0, *) {
            transform(self)
        } else {
            self
        }
    }
}
