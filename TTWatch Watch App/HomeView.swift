//
//  HomeView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/29/25.
//
import SwiftUI

// Verde local solo para esta vista (sin tocar BrandTheme)
private let brand = Color(red: 0.631, green: 0.914, blue: 0.333) // #A1E955

private struct BrandBigButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .heavy))
                .frame(maxWidth: .infinity, minHeight: 76)
                .foregroundStyle(.black)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(brand)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct PillButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .foregroundStyle(brand)
                .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

struct HomeView: View {
    @StateObject private var manager = WatchWorkoutManager()
    @ObservedObject private var wSession = WatchSession.shared

    @State private var goLive = false
    @State private var startedAt: Date = .init()

    private var lastRunLine: String { "Last Run • —" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Header (sin icono Wi-Fi)
                HStack {
                    Text("SportTracker")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(brand)
                    Spacer()
                }

                Text(manager.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Botón grande: SOLO “Start”
                BrandBigButton(title: "Start") {
                    startedAt = Date()
                    manager.start()
                    WKInterfaceDevice.current().play(.start)
                    goLive = true
                }

                // Pills
                HStack(spacing: 8) {
                    PillButton(title: "History") { /* TODO */ }
                    PillButton(title: "Settings") { /* TODO */ }
                }

                // Last run
                HStack {
                    Text(lastRunLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(brand)
                    Spacer()
                }

                Spacer(minLength: 6)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(brand.opacity(0.15))
                    .frame(height: 10)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .onAppear { WatchSession.shared.activate() }
            .navigationDestination(isPresented: $goLive) {
                RunningLiveView(manager: manager, startedAt: startedAt) // ⬅️ pasamos el inicio
            }
        }
    }
}

#Preview { HomeView() }
