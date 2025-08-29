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
    @ObservedObject private var wSession = WatchSession.shared
    
    var body: some View {
        VStack(spacing: 8) {
            Text("SportTracker ⌚️").font(.headline)
            Text(manager.status).font(.footnote)
            HStack {
                Button("Authorize") { manager.requestAuthorization() }
                Button("Start") { manager.start() }
                Button("Stop") { manager.stop() }
            }.font(.caption2)
            //Button("Ping iPhone") { wSession.pingPhone() }
            //    .font(.caption2)
            //Button("Force Activate") { wSession.ensureActivated() }
            Text(wSession.lastReply)
                .font(.caption2)
                .lineLimit(6) // más de 1 línea
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .onAppear { WatchSession.shared.activate() }  
    }
}



#Preview {
    ContentView()
}
