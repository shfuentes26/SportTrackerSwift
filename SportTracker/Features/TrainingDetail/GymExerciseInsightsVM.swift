//
//  GymExerciseInsightsVM.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/1/25.
//
import Foundation
import SwiftData

final class GymExerciseInsightsVM: ObservableObject {
    enum Period: String, CaseIterable, Identifiable {
        case ytd = "YTD", monthly = "Monthly", yearly = "Yearly"
        var id: String { rawValue }
    }

    struct GymPoint: Identifiable {
        let id = UUID()
        let date: Date
        let valueKgOrReps: Double
    }

    @Published var points: [GymPoint] = []
    @Published var isWeighted = false
    @Published var emptyMessage: String? = nil

    private let context: ModelContext
    private let exercise: Exercise
    private let refDate: Date

    init(context: ModelContext, exercise: Exercise, refDate: Date) {
        self.context = context
        self.exercise = exercise
        self.refDate = refDate
        self.isWeighted = exercise.isWeighted
    }

    func load(period: Period) {
        let start = startDate(for: period, ref: refDate)
        let pred  = #Predicate<StrengthSession> { $0.date >= start && $0.date <= refDate }
        let desc  = FetchDescriptor<StrengthSession>(predicate: pred,
                                                     sortBy: [SortDescriptor(\StrengthSession.date, order: .forward)])
        let sessions = (try? context.fetch(desc)) ?? []

        // Agrupado por día: mejor peso o reps de ese ejercicio
        let cal = Calendar.current
        var dayBest: [Date: Double] = [:]
        for s in sessions {
            let sets = s.sets.filter { $0.exercise.id == exercise.id }
            guard !sets.isEmpty else { continue }
            let day = cal.startOfDay(for: s.date)
            let v: Double = exercise.isWeighted
                ? (sets.compactMap { $0.weightKg }.max() ?? 0)
                : Double(sets.map { $0.reps }.max() ?? 0)
            dayBest[day] = max(dayBest[day] ?? 0, v)
        }

        let series = dayBest.keys.sorted().map { d in GymPoint(date: d, valueKgOrReps: dayBest[d] ?? 0) }
        if series.count < 2 { points = []; emptyMessage = "Not enough data to plot" }
        else { points = series; emptyMessage = nil }
    }

    private func startDate(for p: Period, ref: Date) -> Date {
        let cal = Calendar.current
        switch p {
        case .monthly:
            return cal.date(from: cal.dateComponents([.year, .month], from: ref)) ?? ref
        case .ytd:
            return cal.date(from: DateComponents(year: cal.component(.year, from: ref), month: 1, day: 1)) ?? ref
        case .yearly:
            return cal.date(byAdding: .day, value: -365, to: ref) ?? ref
        }
    }
}

