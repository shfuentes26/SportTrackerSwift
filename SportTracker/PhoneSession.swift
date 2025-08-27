//
//  PhoneSession.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
import Foundation
import WatchConnectivity

final class PhoneSession: NSObject, WCSessionDelegate {
    static let shared = PhoneSession()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // Responder a mensajes del Watch
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        if message["ping"] != nil {
            replyHandler(["pong": "hello-from-iphone"])
        } else {
            replyHandler(["ok": true])
        }
    }

    // Requeridos
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
}

