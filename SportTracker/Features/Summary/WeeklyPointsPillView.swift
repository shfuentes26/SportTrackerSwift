//
//  WeeklyPointsPillView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/2/25.
//
import SwiftUI

struct WeeklyPointsPillView: View {
    let runs: [RunningSession]
    let gyms: [StrengthSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("This week you have")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)

                Text("\(weeklyPoints) pts")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(red: 230/255, green: 251/255, blue: 217/255))
        )
        .overlay(
            Capsule().stroke(.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        .contentShape(Capsule())
        .offset(y: 1)   // ⬅️ desplaza la píldora hacia abajo
    }

    // MARK: - Logic
    private var weeklyPoints: Int {
        let di = weekInterval()
        let runPts = runs.filter { di.contains($0.date) }.reduce(0.0) { $0 + $1.totalPoints }
        let gymPts = gyms.filter { di.contains($0.date) }.reduce(0.0) { $0 + $1.totalPoints }
        return Int(runPts + gymPts)
    }

    private func weekInterval(from date: Date = .now) -> DateInterval {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        if let di = cal.dateInterval(of: .weekOfYear, for: date) {
            return di
        }
        let start = cal.startOfDay(for: date)
        return DateInterval(start: start, duration: 7*24*3600)
    }
}

