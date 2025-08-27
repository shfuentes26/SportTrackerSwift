//
//  LiveBar.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
import SwiftUI

struct LiveBar: View {
    @ObservedObject var bridge = LiveWorkoutBridge.shared

    var body: some View {
        HStack(spacing: 16) {
            Text("HR \(bridge.hr)")
            Text(String(format: "%.2f km", bridge.km))
            Text(format(elapsed: bridge.elapsed))
        }
        .font(.footnote)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2, y: 1)
    }

    private func format(elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d:%02d", s/3600, (s/60)%60, s%60)
    }
}

