//
//  WeeklyGymStackedBarChart.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/20/25.
//
import SwiftUI
import Charts
import SwiftData

enum GymGroup: String, CaseIterable, Identifiable {
    case core = "Core"
    case chestBack = "Chest/Back"
    case arms = "Arms"
    case legs = "Legs"
    var id: String { rawValue }
}

struct GymDailyGroupCount: Identifiable {
    let id = UUID()
    let day: Date
    let group: GymGroup
    let count: Int
}

struct WeeklyGymStackedBarChart: View {
    let sessions: [StrengthSession]
    let weekStart: Date                 // Monday 00:00 of the selected week

    // Change if you prefer sets/points
    private let metric: Metric = .uniqueExercises
    enum Metric { case uniqueExercises, sets, points }

    var body: some View {
        let data = aggregateWeeklyData()
        let weekEnd = Calendar.iso8601MondayEN.date(byAdding: .day, value: 6, to: weekStart)!

        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly summary (by day)")
                .font(.headline)

            if data.isEmpty {
                ContentUnavailableView("No sessions this week", systemImage: "rectangle.3.group.bubble")
            } else {
                Chart(data) { dp in
                    // One bar per day; stacked segments by group
                    BarMark(
                        x: .value("Day", dp.day, unit: .day),
                        y: .value("Count", dp.count)
                    )
                    .foregroundStyle(by: .value("Group", dp.group.rawValue))
                }
                // Always show Mon→Sun
                .chartXScale(domain: weekStart ... weekEnd)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                        AxisTick()
                        if let d = value.as(Date.self) {
                            AxisValueLabel(d.weekdayLabelEN)
                        }
                    }
                }
                .chartForegroundStyleScale(domain: GymChartPalette.domain,
                                           range:  GymChartPalette.colors)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .frame(height: 140) // compact height
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Aggregation (merge all sessions on the same day)
    private func aggregateWeeklyData() -> [GymDailyGroupCount] {
        let cal = Calendar.iso8601MondayEN
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return [] }

        let weekSessions = sessions.filter { (weekStart ... weekEnd.addingTimeInterval(-1)).contains($0.date) }

        var perDayGroup: [Date: [GymGroup: Int]] = [:]

        for sess in weekSessions {
            let day = cal.startOfDay(for: sess.date)

            switch metric {
            case .uniqueExercises:
                var seen: [GymGroup: Set<UUID>] = [:]
                for set in sess.sets {
                    if let grp = mapGroup(set.exercise.muscleGroup) {
                        seen[grp, default: []].insert(set.exercise.id)
                    }
                }
                for (grp, uniq) in seen {
                    perDayGroup[day, default: [:]][grp, default: 0] += uniq.count
                }

            case .sets:
                var counts: [GymGroup: Int] = [:]
                for set in sess.sets {
                    if let grp = mapGroup(set.exercise.muscleGroup) {
                        counts[grp, default: 0] += 1
                    }
                }
                for (grp, c) in counts {
                    perDayGroup[day, default: [:]][grp, default: 0] += c
                }

            case .points:
                var pts: [GymGroup: Int] = [:]
                for set in sess.sets {
                    if let grp = mapGroup(set.exercise.muscleGroup) {
                        // Replace with your points logic if you have one
                        let add = max(1, set.reps)
                        pts[grp, default: 0] += add
                    }
                }
                for (grp, p) in pts {
                    perDayGroup[day, default: [:]][grp, default: 0] += p
                }
            }
        }

        var out: [GymDailyGroupCount] = []
        for i in 0..<7 {
            guard let day = Calendar.iso8601MondayEN.date(byAdding: .day, value: i, to: weekStart) else { continue }
            for (grp, c) in (perDayGroup[day] ?? [:]) where c > 0 {
                out.append(GymDailyGroupCount(day: day, group: grp, count: c))
            }
        }
        return out
    }

    private func mapGroup(_ g: MuscleGroup) -> GymGroup? {
        switch g {
        case .core:      return .core
        case .chestBack: return .chestBack
        case .arms:      return .arms
        case .legs:      return .legs
        default:         return nil
        }
    }
    // Fixed palette for Gym groups (reusable across charts)
    struct GymChartPalette {
        static let domain: [String] = [
            GymGroup.chestBack.rawValue,
            GymGroup.arms.rawValue,
            GymGroup.legs.rawValue,
            GymGroup.core.rawValue
        ]
        static let colors: [Color] = [
            .blue,   // Chest/Back
            .orange, // Arms
            .green,  // Legs
            .purple  // Core
        ]
    }
}

// MARK: - Date/Calendar utils (English, Monday-first)
fileprivate extension Calendar {
    static var iso8601MondayEN: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()
}

fileprivate extension Date {
    // Compact English labels: Mon→"M", Tue→"Tu", Wed→"W", Thu→"Th", Fri→"F", Sat→"Sa", Sun→"Su"
    var weekdayLabelEN: String {
        let cal = Calendar.iso8601MondayEN
        let wd = cal.component(.weekday, from: self)
        switch wd {
        case 2: return "M"    // Mon
        case 3: return "Tu"   // Tue
        case 4: return "W"    // Wed
        case 5: return "Th"   // Thu
        case 6: return "F"    // Fri
        case 7: return "Sa"   // Sat
        default: return "Su"  // Sun (1)
        }
    }
}

