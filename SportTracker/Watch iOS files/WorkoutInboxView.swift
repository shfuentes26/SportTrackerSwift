//
//  WorkoutInboxView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/28/25.
//
import SwiftUI

struct WorkoutInboxView: View {
    @ObservedObject private var inbox = WorkoutInbox.shared

    var body: some View {
        List(inbox.items, id: \.id) { w in
            VStack(alignment: .leading, spacing: 4) {
                Text(w.start, style: .date) + Text("  ") + Text(w.start, style: .time)
                Text(String(format: "%.2f km • avgHR %@ • %d splits",
                            (w.distanceMeters ?? 0)/1000.0,
                            w.avgHR != nil ? String(Int(w.avgHR!)) : "—",
                            w.kmSplits?.count ?? 0))
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Inbox (Watch)")
        .onAppear { inbox.reload() }
    }
}

