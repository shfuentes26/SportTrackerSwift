//
//  WatchSession.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
import Foundation
import WatchConnectivity

final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()
    @Published var lastReply = "—"

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // Enviamos un ping al iPhone
    func pingPhone() {
        guard WCSession.default.isReachable else {
            lastReply = "Phone not reachable"
            return
        }
        WCSession.default.sendMessage(["ping": "hello-from-watch"], replyHandler: { reply in
            DispatchQueue.main.async { self.lastReply = "Reply: \(reply)" }
        }, errorHandler: { error in
            DispatchQueue.main.async { self.lastReply = "Error: \(error.localizedDescription)" }
        })
    }

    // Requeridos
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) { }
}

