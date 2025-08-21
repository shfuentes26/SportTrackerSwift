//
//  GoalsSettingsView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/21/25.
//
import SwiftUI
import SwiftData

struct GoalsSettingsView: View {
    @Environment(\.modelContext) private var context

    @Query private var runningGoals: [RunningGoal]
    @Query private var gymGoals: [GymGoal]

    // Aseguradores: 1 running goal y 1 gym goal como mucho
    private func ensureRunningGoal() -> RunningGoal {
        if let g = runningGoals.first { return g }
        let g = RunningGoal(weeklyKilometers: 0)
        context.insert(g)
        try? context.save()
        return g
    }
    private func ensureGymGoal() -> GymGoal {
        if let g = gymGoals.first { return g }
        let g = GymGoal()
        context.insert(g)
        try? context.save()
        return g
    }

    var body: some View {
        let rg = ensureRunningGoal()
        let gg = ensureGymGoal()
        @Bindable var brg = rg
        @Bindable var bgg = gg

        Form {
            Section("Running") {
                HStack {
                    Text("Weekly target")
                    Spacer()
                    TextField("0", value: $brg.weeklyKilometers, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("km").foregroundStyle(.secondary)
                }
            }

            Section("Gym • Weekly target per group") {
                Stepper("Chest/Back: \(bgg.targetChestBack)", value: $bgg.targetChestBack, in: 0...14)
                Stepper("Arms: \(bgg.targetArms)", value: $bgg.targetArms, in: 0...14)
                Stepper("Legs: \(bgg.targetLegs)", value: $bgg.targetLegs, in: 0...14)
                Stepper("Core: \(bgg.targetCore)", value: $bgg.targetCore, in: 0...14)
            }

            Section {
                Button {
                    try? context.save()
                } label: {
                    Label("Save goals", systemImage: "checkmark.circle.fill")
                }
            }
        }
        .navigationTitle("Goals")
    }
}

