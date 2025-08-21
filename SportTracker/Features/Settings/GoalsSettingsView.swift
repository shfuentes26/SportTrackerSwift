import SwiftUI
import SwiftData

enum GoalTab: String, CaseIterable, Identifiable {
    case running = "Running"
    case gym     = "Gym"
    var id: Self { self }
}

struct GoalsSettingsView: View {
    @Environment(\.modelContext) private var context

    @Query private var runningGoals: [RunningGoal]
    @Query private var gymGoals: [GymGoal]

    @State private var selectedTab: GoalTab
    @State private var showSaved = false
    @State private var savedMessage = "Goal saved ✅"

    init(selectedTab: GoalTab = .running) {
        _selectedTab = State(initialValue: selectedTab)
    }

    private func ensureRunningGoal() -> RunningGoal {
        if let g = runningGoals.first { return g }
        let g = RunningGoal(weeklyKilometers: 0)
        context.insert(g); try? context.save()
        return g
    }
    private func ensureGymGoal() -> GymGoal {
        if let g = gymGoals.first { return g }
        let g = GymGoal()
        context.insert(g); try? context.save()
        return g
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tabs FUERA del Form (igual que en New Training)
            Picker("Goal type", selection: $selectedTab) {
                ForEach(GoalTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // ===== Franja blanca bajo los tabs (acolchado visual) =====
            Color(.systemBackground)          // ← banda blanca
                .frame(height: 4)            // ajusta 8–12 si quieres
                .padding(.horizontal)          // mismo inset que los cards
                .padding(.top, 4)              // micro separación del Picker
                .allowsHitTesting(false)

            // Form: primera fila sin Section (como en New)
            Form {
                if selectedTab == .running {
                    let rg = ensureRunningGoal()
                    @Bindable var brg = rg

                    LabeledContent("Weekly target") {
                        HStack(spacing: 6) {
                            TextField(
                                "0",
                                value: $brg.weeklyKilometers,
                                format: .number.precision(.fractionLength(0...1))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            Text("km").foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button {
                            do {
                                try context.save()
                                savedMessage = "Running goal saved ✅"
                                showSaved = true
                                #if canImport(UIKit)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                #endif
                            } catch {
                                savedMessage = "Error saving goal: \(error.localizedDescription)"
                                showSaved = true
                            }
                        } label: {
                            Label("Save running goal", systemImage: "checkmark.circle.fill")
                        }
                    }

                } else {
                    let gg = ensureGymGoal()
                    @Bindable var bgg = gg

                    Stepper("Chest/Back: \(bgg.targetChestBack)", value: $bgg.targetChestBack, in: 0...14)
                    Stepper("Arms: \(bgg.targetArms)", value: $bgg.targetArms, in: 0...14)
                    Stepper("Legs: \(bgg.targetLegs)", value: $bgg.targetLegs, in: 0...14)
                    Stepper("Core: \(bgg.targetCore)", value: $bgg.targetCore, in: 0...14)

                    Section {
                        Button {
                            do {
                                try context.save()
                                savedMessage = "Gym goal saved ✅"
                                showSaved = true
                                #if canImport(UIKit)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                #endif
                            } catch {
                                savedMessage = "Error saving goal: \(error.localizedDescription)"
                                showSaved = true
                            }
                        } label: {
                            Label("Save gym goal", systemImage: "checkmark.circle.fill")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Goals")
        .brandHeaderSpacer()
        .alert("Saved", isPresented: $showSaved) {
            Button("OK", role: .cancel) { }
        } message: { Text(savedMessage) }
    }
}
