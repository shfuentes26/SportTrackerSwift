//
//  GymExerciseInsightsView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/1/25.
//
import SwiftUI
import SwiftData
import Charts

struct GymExerciseInsightsView: View {
    typealias Period = GymExerciseInsightsVM.Period

    @StateObject private var vm: GymExerciseInsightsVM

    let exerciseName: String
    let usePounds: Bool

    @State private var period: Period = .ytd

    init(exercise: Exercise, currentSession: StrengthSession, usePounds: Bool, context: ModelContext) {
        _vm = StateObject(wrappedValue: GymExerciseInsightsVM(context: context,
                                                              exercise: exercise,
                                                              refDate: currentSession.date))
        self.exerciseName = exercise.name
        self.usePounds = usePounds
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 6) {
                    Text(exerciseName).font(.title3).bold()
                    Text(vm.isWeighted ? "Max weight per day" : "Max reps per day")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 2)

                if let msg = vm.emptyMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text(msg).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Chart(vm.points) { p in
                        LineMark(x: .value("Date", p.date),
                                 y: .value(vm.isWeighted ? (usePounds ? "lb" : "kg") : "reps",
                                           displayValue(p.valueKgOrReps)))
                        PointMark(x: .value("Date", p.date),
                                  y: .value(vm.isWeighted ? (usePounds ? "lb" : "kg") : "reps",
                                            displayValue(p.valueKgOrReps)))
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .chartYAxis { AxisMarks() }
                    .frame(height: 260)

                    if let last = vm.points.last {
                        let lastStr = vm.isWeighted ? displayWeight(last.valueKgOrReps)
                                                    : String(format: "%.0f reps", last.valueKgOrReps)
                        let bestVal = vm.points.map(\.valueKgOrReps).max() ?? last.valueKgOrReps
                        let bestStr = vm.isWeighted ? displayWeight(bestVal)
                                                    : String(format: "%.0f reps", bestVal)
                        Text("Last: \(lastStr) • Best: \(bestStr)")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.load(period: period) }
            .onChange(of: period) { vm.load(period: $0) }
        }
    }

    // MARK: helpers
    // GymExerciseInsightsView.swift
    private func displayWeight(_ kg: Double) -> String {
        let val = usePounds ? UnitFormatters.kgToLb(kg) : kg
        let unit = usePounds ? "lb" : "kg"
        let fmt = usePounds ? "%.0f %@" : "%.1f %@"
        return String(format: fmt, val, unit)
    }
    private func displayValue(_ v: Double) -> Double {
        vm.isWeighted ? (usePounds ? UnitFormatters.kgToLb(v) : v) : v
    }
}

