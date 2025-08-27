//
//  ContentView.swift
//  TTWatch Watch App
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//

// TTWatch Watch App -> ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = WatchWorkoutManager()
    @StateObject private var wSession = WatchSession.shared

    var body: some View {
        VStack(spacing: 8) {
            Text("SportTracker ⌚️").font(.headline)
            Text(manager.status).font(.footnote)
            HStack {
                Button("Authorize") { manager.requestAuthorization() }
                Button("Start") { manager.start() }
                Button("Stop") { manager.stop() }
            }.font(.caption2)
            Button("Ping iPhone") { wSession.pingPhone() }
                .font(.caption2)
            Text(wSession.lastReply).font(.footnote).multilineTextAlignment(.center)
        }
        .padding()
    }
}



#Preview {
    ContentView()
}
