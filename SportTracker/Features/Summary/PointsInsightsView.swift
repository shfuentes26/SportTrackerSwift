//
//  PointsInsightsView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/2/25.
//
import SwiftUI
import Charts

struct PointsInsightsView: View {
    let runs: [RunningSession]
    let gyms: [StrengthSession]

    enum Tab: String, CaseIterable { case weekly = "Weekly", monthly = "Monthly", yearly = "Yearly" }
    @State private var tab: Tab = .weekly
    @State private var selectedIndex: Int?

    // Paginación por chevrons para Weekly y Monthly
    @State private var weekPage: Int = 0     // 0 = últimas 12 semanas; 1 = 12 previas; etc.
    @State private var monthPage: Int = 0    // 0 = últimos 12 meses; 1 = 12 previos; etc.

    var body: some View {
        VStack(spacing: 12) {
            // Tabs
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Controles de paginación con chevrons (solo Weekly/Monthly)
            if tab != .yearly {
                HStack(spacing: 10) {
                    Button {
                        // IZQUIERDA = ir al pasado (más antiguo)
                        switch tab {
                        case .weekly:  weekPage += 1
                        case .monthly: monthPage += 1
                        case .yearly:  break
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoOlder) // <- deshabilitar si NO hay datos más antiguos

                    Text(rangeLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    Button {
                        // DERECHA = volver a recientes
                        switch tab {
                        case .weekly:  weekPage = max(0, weekPage - 1)
                        case .monthly: monthPage = max(0, monthPage - 1)
                        case .yearly:  break
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(isNewestPage)
                }
                .padding(.horizontal)
            }

            // --- Gráfico compacto con barras y selección ---
            Chart {
                ForEach(dataForCurrentTab) { item in
                    BarMark(
                        x: .value("Period", item.label),
                        y: .value("Points", item.points)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.75))
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        Text("\(item.points)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .annotation(position: .overlay, alignment: .center) {
                        if isSelected(item) {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.blue.opacity(0.9), lineWidth: 2)
                                .shadow(color: Color.blue.opacity(0.25), radius: 3)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.35))
                    AxisTick().foregroundStyle(Color.secondary.opacity(0.55))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: dataForCurrentTab.map(\.label)) { value in
                    let label = value.as(String.self) ?? ""
                    let selected = (label == selectedBucket?.label)
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(.clear)
                    AxisValueLabel { Text(label) }
                        .font(selected ? .footnote.weight(.semibold) : .caption2)
                        .foregroundStyle(selected ? .primary : .secondary)
                }
            }
            .frame(height: 220)
            .padding(.horizontal)
            .chartOverlay { proxy in
                // Solo para seleccionar barras (sin swipe)
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged { value in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let xInPlot = value.location.x - origin.x
                                if let label: String = proxy.value(atX: xInPlot),
                                   let idx = dataForCurrentTab.firstIndex(where: { $0.label == label }) {
                                    selectedIndex = idx
                                }
                            }
                        )
                }
            }

            // Faja “Viewing”
            if let sel = selectedBucket {
                HStack(spacing: 8) {
                    Text("Viewing:")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(activeTitle(for: sel))
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.opacity(0.12)))
                        .overlay(Capsule().stroke(Color.blue.opacity(0.35)))
                    Spacer()
                }
                .padding(.horizontal)
            }

            // --- Lista del período seleccionado ---
            Group {
                if let idx = effectiveSelectedIndex,
                   dataForCurrentTab.indices.contains(idx) {

                    let sel = dataForCurrentTab[idx]
                    let items = pointItems(for: sel.interval)

                    HStack {
                        Text(titleForSelected(sel)).font(.headline)
                        Spacer()
                        Text("\(items.reduce(0) { $0 + $1.points }) pts")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    List {
                        ForEach(items) { it in
                            HStack(spacing: 12) {
                                Image(systemName: it.kind == .run ? "figure.run" : "dumbbell.fill")
                                    .imageScale(.medium)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.title).font(.body)
                                    Text(dateFormatter.string(from: it.date))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(it.points)")
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Text("No sessions for the selected period")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
        }
        .brandHeaderSpacer()
        .navigationTitle("Points")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selectedIndex == nil { selectedIndex = (dataForCurrentTab.count - 1) } }
        .onChange(of: tab) { _ in
            selectedIndex = (dataForCurrentTab.count - 1)
            // reset de paginación al cambiar de tab
            if tab == .weekly { weekPage = 0 }
            if tab == .monthly { monthPage = 0 }
        }
        // al paginar, selecciona el último bucket visible (más reciente de esa página)
        .onChange(of: weekPage) { _ in selectedIndex = (dataForCurrentTab.count - 1) }
        .onChange(of: monthPage) { _ in selectedIndex = (dataForCurrentTab.count - 1) }
    }

    // MARK: - Data

    private var dataForCurrentTab: [PointBucket] {
        switch tab {
        case .weekly:
            // 12 semanas por página; ancla desplazada weekPage * 12 semanas hacia atrás
            return buckets(by: .weekOfYear, count: 12, dateFormat: "w",
                           anchor: Calendar.current.date(byAdding: .weekOfYear, value: -(weekPage * 12), to: Date())!)
        case .monthly:
            // 12 meses por página
            return buckets(by: .month, count: 12, dateFormat: "MMM",
                           anchor: Calendar.current.date(byAdding: .month, value: -(monthPage * 12), to: Date())!)
        case .yearly:
            // años recientes (sin paginación de momento)
            return buckets(by: .year, count: 7, dateFormat: "yyyy", anchor: Date())
        }
    }

    // Label del rango visible para mostrar entre los chevrons
    private var rangeLabel: String {
        let labels = dataForCurrentTab.map(\.label)
        guard let first = labels.first, let last = labels.last else { return "" }
        switch tab {
        case .weekly:  return "Weeks \(first)–\(last)"
        case .monthly: return "\(first) – \(last)"
        case .yearly:  return ""
        }
    }

    // ¿Estamos ya en la página más reciente?
    private var isNewestPage: Bool {
        switch tab {
        case .weekly:  return weekPage == 0
        case .monthly: return monthPage == 0
        case .yearly:  return true
        }
    }

    // ¿Hay datos más antiguos que la página actual?
    private var canGoOlder: Bool {
        guard let oldestStart = dataForCurrentTab.first?.interval.start,
              let earliest = earliestSessionDate else { return false }
        // Si existe alguna sesión más antigua que el inicio del primer bucket visible,
        // sí podemos ir a páginas más antiguas.
        return earliest < oldestStart
    }

    // Fecha más antigua en runs/gyms
    private var earliestSessionDate: Date? {
        let earliestRun = runs.min(by: { $0.date < $1.date })?.date
        let earliestGym = gyms.min(by: { $0.date < $1.date })?.date
        switch (earliestRun, earliestGym) {
        case let (r?, g?): return min(r, g)
        case let (r?, nil): return r
        case let (nil, g?): return g
        default: return nil
        }
    }

    private var selectedBucket: PointBucket? {
        guard let i = effectiveSelectedIndex, dataForCurrentTab.indices.contains(i) else { return nil }
        return dataForCurrentTab[i]
    }
    private func isSelected(_ item: PointBucket) -> Bool {
        guard let sel = selectedBucket else { return false }
        return sel.id == item.id
    }

    /// Construye buckets de puntos para un componente de calendario,
    /// tomando `count` periodos hacia atrás desde `anchor` (inclusive).
    private func buckets(by component: Calendar.Component,
                         count: Int,
                         dateFormat: String,
                         anchor: Date) -> [PointBucket] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday

        // Construye las fechas "hacia atrás" desde el anchor
        let dates: [Date] = (0..<count).compactMap { offset in
            cal.date(byAdding: component, value: -offset, to: anchor)
        }.reversed() // oldest -> newest

        let fmt = DateFormatter(); fmt.setLocalizedDateFormatFromTemplate(dateFormat)

        return dates.map { date in
            let di = cal.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 1)
            let r = runs.filter { di.contains($0.date) }.reduce(0.0) { $0 + $1.totalPoints }
            let g = gyms.filter { di.contains($0.date) }.reduce(0.0) { $0 + $1.totalPoints }
            return PointBucket(label: fmt.string(from: di.start), points: Int(r + g), interval: di)
        }
    }

    // MARK: - Selection helpers
    private var effectiveSelectedIndex: Int? {
        if let idx = selectedIndex, dataForCurrentTab.indices.contains(idx) { return idx }
        return dataForCurrentTab.isEmpty ? nil : dataForCurrentTab.count - 1
    }

    private func activeTitle(for bucket: PointBucket) -> String {
        switch tab {
        case .weekly:  return "Week \(bucket.label)"
        case .monthly: return bucket.label
        case .yearly:  return bucket.label
        }
    }

    private func titleForSelected(_ bucket: PointBucket) -> String {
        switch tab {
        case .weekly:  return "Sessions this week (\(bucket.label))"
        case .monthly: return "Sessions in \(bucket.label)"
        case .yearly:  return "Sessions in \(bucket.label)"
        }
    }

    // MARK: - Build list items for a DateInterval
    private func pointItems(for interval: DateInterval) -> [PointItem] {
        var items: [PointItem] = []
        for r in runs where interval.contains(r.date) {
            items.append(PointItem(date: r.date, title: "Running session", points: Int(r.totalPoints), kind: .run))
        }
        for g in gyms where interval.contains(g.date) {
            items.append(PointItem(date: g.date, title: "Gym session", points: Int(g.totalPoints), kind: .gym))
        }
        return items.sorted { $0.date > $1.date }
    }

    // MARK: - Models
    private struct PointBucket: Identifiable {
        let id = UUID()
        let label: String
        let points: Int
        let interval: DateInterval
    }
    private enum ItemKind { case run, gym }
    private struct PointItem: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let points: Int
        let kind: ItemKind
    }

    // MARK: - Formatters
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
