//
//  ContentView.swift
//  TTWatch Watch App
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//

// TTWatch Watch App -> ContentView.swift
// TTWatch Watch App -> ContentView.swift
import SwiftUI

// Botón cápsula primario (verde)
private struct BrandCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color.brand.opacity(0.7) : Color.brand)
            .foregroundStyle(.black)
            .clipShape(Capsule())
    }
}

// Botón secundario bordeado
private struct BorderedSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .overlay(
                Capsule()
                    .stroke(Color.brand.opacity(configuration.isPressed ? 0.5 : 1), lineWidth: 1.5)
            )
            .foregroundStyle(Color.brand)
    }
}

struct ContentView: View {
    @StateObject private var manager = WatchWorkoutManager()
    @ObservedObject private var wSession = WatchSession.shared

    var body: some View {
        ScrollView {                               // 👈 evita que el texto largo “expulse” los botones
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    HStack {
                        Text("Training Tracker").font(.headline)
                        Spacer()
                        // pequeño indicador WC si quieres (opcional)
                        Image(systemName: "applewatch.watchface")
                            .foregroundStyle(.secondary)
                    }
                    Text(manager.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Botón principal
                Button {
                    manager.start()
                    WKInterfaceDevice.current().play(.start)
                } label: {
                    VStack(spacing: 2) {
                        Text("Start Running")
                        Text("Countdown 3s").font(.caption2).opacity(0.8)
                    }
                }
                .buttonStyle(BrandCapsuleButtonStyle())

                // Acciones secundarias
                HStack(spacing: 8) {
                    Button("Authorize") {
                        manager.requestAuthorization()
                    }
                    .buttonStyle(BorderedSmallButtonStyle())

                    Button("Stop") {
                        manager.stop()
                        WKInterfaceDevice.current().play(.stop)
                    }
                    .buttonStyle(BorderedSmallButtonStyle())
                    .tint(.red)
                }

                // Estado / enlace iPhone
                VStack(alignment: .leading, spacing: 4) {
                    Text("iPhone link").font(.caption2).foregroundStyle(.secondary)
                    Text(wSession.lastReply)
                        .font(.caption2)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
        .onAppear {
            WatchSession.shared.activate()
        }
    }
}

#Preview { ContentView() }
