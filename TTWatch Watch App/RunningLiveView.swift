//
//  RunningLiveView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/29/25.
//
import SwiftUI

// Verde local (no tocamos BrandTheme / assets)
private let brand = Color(red: 0.631, green: 0.914, blue: 0.333) // #A1E955

struct RunningLiveView: View {
    @ObservedObject var manager: WatchWorkoutManager
    let startedAt: Date

    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    @State private var paused = false
    @State private var lastKm: Double = 0

    // Punto de referencia: si el manager ya tiene start en vivo, úsalo
    private var startRef: Date { manager.liveStartDate ?? startedAt }

    // Tiempo transcurrido
    private var elapsed: TimeInterval { max(0, now.timeIntervalSince(startRef)) }

    private var elapsedText: String {
        // antes: let t = Int(elapsed.rounded())
        let t = Int(elapsed) // truncado → evita saltos de 2s
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }

    // Distancia y HR en vivo
    private var distKm: Double {
        paused ? lastKm : manager.liveKm     // 👈 usa el buffer si está en pausa
    }
    private var hrText: String { manager.liveHR.map(String.init) ?? "—" }

    // Pace: usa el publicado si está; si no, calcula por tiempo/distancia
    private var paceText: String {
        func fmt(_ p: Double?) -> String {
            // protegemos: nil, NaN, ±∞, 0 o valores absurdos
            guard let p, p.isFinite, p > 0 else { return "—:—" }
            // clamp a un máximo razonable (p.ej., 99 min/km)
            let capped = min(p, 99 * 60)
            let total = Int(capped.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }

        if let published = manager.livePaceSecPerKm {
            return fmt(published)
        }
        // fallback a cálculo por tiempo/distancia
        guard distKm > 0 else { return "—:—" }
        return fmt(elapsed / distKm)
    }

    var body: some View {
        VStack(spacing: 8) {
            // TIEMPO + DISTANCIA usando TimelineView para ticks estables de 1s
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    // TIEMPO — grande y centrado
                    let elapsedNow = max(0, context.date.timeIntervalSince(startRef))
                    let t = Int(elapsedNow) // truncado
                    let h = t / 3600, m = (t % 3600) / 60, s = t % 60
                    let timeStr = h > 0
                        ? String(format: "%d:%02d:%02d", h, m, s)
                        : String(format: "%02d:%02d", m, s)

                    Text(timeStr)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(brand)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // DISTANCIA — grande y centrada
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.2f", distKm))
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(brand)
                        Text("km")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(brand.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            // HR / Pace compactos
            /*HStack {
                VStack(spacing: 0) {
                    Text(hrText)
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(brand)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 18)
                VStack(spacing: 0) {
                    Text(paceText)
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(brand)
                    Text("min/km")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
             */
            // Botones inferiores
            HStack(spacing: 8) {
                Button {
                    if paused {
                        manager.resume()
                    } else {
                        manager.pause()
                    }
                    paused.toggle()
                    WKInterfaceDevice.current().play(.directionUp)
                } label: {
                    Text(paused ? "Resume" : "Pause")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .tint(brand)

                Button {
                    WKInterfaceDevice.current().play(.stop)
                    manager.stop()
                    dismiss()
                } label: {
                    Text("Stop")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.horizontal, 12)
        .navigationBarBackButtonHidden(true)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if !paused {
                now = Date()
                lastKm = manager.liveKm          // 👈 cache mientras está en marcha
            }
        }
    }
}
