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
    private let refDate: Date   // solo para referencia; no corta el rango superior

    init(context: ModelContext, exercise: Exercise, refDate: Date) {
        self.context = context
        self.exercise = exercise
        self.refDate = refDate
        self.isWeighted = exercise.isWeighted
    }

    func load(period: Period) {
        let now = Date()
        let start = startDate(for: period, ref: now)

        let pred  = #Predicate<StrengthSession> { $0.date >= start && $0.date <= now }
        let desc  = FetchDescriptor<StrengthSession>(
            predicate: pred,
            sortBy: [SortDescriptor(\StrengthSession.date, order: .forward)]
        )
        let sessions = (try? context.fetch(desc)) ?? []

        // Mejor valor del ejercicio por día
        let cal = Calendar.current
        var dayBest: [Date: Double] = [:]

        for s in sessions {
            // Filtra sets del ejercicio actual manejando opcionales
            let setsForExercise = (s.sets ?? [])
                .filter { $0.exercise?.id == exercise.id }

            guard !setsForExercise.isEmpty else { continue }

            let day = cal.startOfDay(for: s.date)
            let v: Double = exercise.isWeighted
                ? (setsForExercise.compactMap { $0.weightKg }.max() ?? 0)
                : Double(setsForExercise.map { $0.reps }.max() ?? 0)

            dayBest[day] = max(dayBest[day] ?? 0, v)
        }

        let series = dayBest.keys.sorted().map { d in
            GymPoint(date: d, valueKgOrReps: dayBest[d] ?? 0)
        }
        self.points = series
        self.emptyMessage = series.isEmpty ? "No data to display." : nil
        self.isWeighted = exercise.isWeighted
    }


    private func startDate(for p: Period, ref: Date) -> Date {
        let cal = Calendar.current
        switch p {
        case .ytd:
            // 1 de enero del año actual
            return cal.date(from: DateComponents(year: cal.component(.year, from: ref), month: 1, day: 1)) ?? ref
        case .monthly:
            // TODO clave: Monthly debe cubrir el AÑO actual completo para poder agregar por MES
            return cal.date(from: DateComponents(year: cal.component(.year, from: ref), month: 1, day: 1)) ?? ref
        case .yearly:
            // Histórico completo
            return Date.distantPast
        }
    }
}
