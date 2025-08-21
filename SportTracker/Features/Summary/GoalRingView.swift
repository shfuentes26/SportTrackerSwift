//
//  GoalRingView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/21/25.
//
import SwiftUI

struct GoalRingView: View {
    var title: String
    var progress: Double      // 0...1
    var subtitle: String?

    private let lineWidth: CGFloat = 12

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(round(progress * 100)))%")
                    .font(.title3).monospacedDigit()
            }
            .frame(width: 110, height: 110)

            Text(title).font(.headline)
            if let s = subtitle { Text(s).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

