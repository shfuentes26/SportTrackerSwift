//
//  GymSessionDetail.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/1/25.
//
import SwiftUI
import SwiftData

struct GymSessionDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [Settings]
    private var usePounds: Bool { settingsList.first?.prefersPounds ?? false }

    let session: StrengthSession

    @State private var showDelete = false
    @State private var showEdit = false

    // Sheet usando item para evitar pantallas blancas
    @State private var showExercisePicker = false
    @State private var selectedExercise: Exercise? = nil

    var body: some View {
        List {
            Section("SETS") {
                ForEach(sortedSets, id: \.id) { set in
                    GymSetRow(set: set, usePounds: usePounds)
                }
            }

            if let notes = session.notes, !notes.isEmpty {
                Section("NOTES") { Text(notes) }
            }

            Section("SUMMARY") {
                HStack { Text("Date"); Spacer(); Text(SummaryView.formatDate(session.date)).foregroundStyle(.secondary) }
                HStack { Text("Points"); Spacer(); Text("\(Int(session.totalPoints)) pts").foregroundStyle(.secondary).monospacedDigit() }
            }

            // --- INSIGHTS (pill con mismo ancho que las secciones de arriba) ---
            if !insightExercises.isEmpty {
                Button {
                    if insightExercises.count == 1 {
                        selectedExercise = insightExercises.first
                    } else { showExercisePicker = true }
                } label: {
                    HStack(spacing: 10) {
                        // Texto + icono en azul
                        HStack(spacing: 10) {
                            Image(systemName: "chart.xyaxis.line")
                            Text("Insights").font(.headline)
                        }
                        .foregroundStyle(.blue)

                        Spacer()

                        // Chevron de navegación (gris)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .systemBlue).opacity(0.12))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // iguala el ancho a las celdas de Section (ajusta 16→20 si tu lista usa ese margen)
                .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

        }
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
                Button(role: .destructive) { showDelete = true } label: { Text("Delete") }
            }
        }
        .confirmationDialog("Choose exercise", isPresented: $showExercisePicker) {
            ForEach(insightExercises, id: \.id) { ex in
                Button(ex.name) { selectedExercise = ex }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete workout?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(session); try? context.save(); dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedExercise) { ex in
            GymExerciseInsightsView(exercise: ex, currentSession: session, usePounds: usePounds, context: context)
        }
        .sheet(isPresented: $showEdit) {
            EditGymSheet(session: session)
        }
    }

    private var sortedSets: [StrengthSet] {
        (session.sets ?? []).sorted { a, b in
            a.order != b.order ? a.order < b.order : a.id.uuidString < b.id.uuidString
        }
    }

    private var insightExercises: [Exercise] {
        var seen = Set<UUID>()
        var result: [Exercise] = []
        for set in (session.sets ?? []) {
            guard let ex = set.exercise else { continue }
            if !seen.contains(ex.id), hasHistory(for: ex) {
                seen.insert(ex.id)
                result.append(ex)
            }
        }
        return result.sorted { $0.name < $1.name }
    }


    private func hasHistory(for ex: Exercise) -> Bool {
        let desc = FetchDescriptor<StrengthSession>(
            sortBy: [SortDescriptor(\StrengthSession.date, order: .reverse)]
        )
        guard let sessions = try? context.fetch(desc), !sessions.isEmpty else { return false }

        var count = 0
        for s in sessions where (s.sets ?? []).contains(where: { $0.exercise?.id == ex.id }) {
            count += 1
            if count >= 2 { return true }
        }
        return false
    }

}

struct GymSetRow: View {
    let set: StrengthSet
    let usePounds: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(set.exercise?.name ?? "Exercise").font(.headline)
                Text("• \(groupName(set.exercise?.muscleGroup ?? .arms))")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
            }
            HStack(spacing: 12) {
                Text("Reps: \(set.reps)")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                if let wKg = set.weightKg, wKg > 0 {
                    let value = usePounds ? UnitFormatters.kgToLb(wKg) : wKg
                    let unit  = usePounds ? "lb" : "kg"
                    let fmt   = usePounds ? "%.0f" : "%.1f"
                    Text("Weight: \(String(format: fmt, value)) \(unit)")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func groupName(_ g: MuscleGroup) -> String {
        switch g {
        case .chestBack: return "Chest/Back"
        case .arms:      return "Arms"
        case .legs:      return "Legs"
        case .core:      return "Core"
        @unknown default: return "Other"
        }
    }
}


