//
//  SummarySheet.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
import SwiftUI

struct SummarySheet: View {
    let summary: WorkoutSummary
    var onClose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Workout summary").font(.headline)
            Text(String(format: "Distance: %.2f km", summary.distanceKm))
            Text("Avg HR: \(summary.avgHR) bpm")
            Text(duration(summary.end.timeIntervalSince(summary.start)))
            HStack {
                Button("Dismiss") { onClose(false) }
                Button("Save") { onClose(true) }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func duration(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format:"%02d:%02d:%02d", s/3600,(s/60)%60,s%60)
    }
}

