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
    @Published var reachable = false
    @Published var state: WCSessionActivationState = .notActivated

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // Ping de prueba (lo sigues usando desde el botón)
    func pingPhone() {
        guard WCSession.default.isReachable else {
            lastReply = "Phone not reachable"
            return
        }
        WCSession.default.sendMessage(["ping": "hello-from-watch"],
                                      replyHandler: { reply in
            DispatchQueue.main.async { self.lastReply = "Reply: \(reply)" }
        }, errorHandler: { error in
            DispatchQueue.main.async { self.lastReply = "Error: \(error.localizedDescription)" }
        })
    }

    // Envío de datos en vivo al iPhone
    func sendUpdate(hr: Int, distanceKm: Double, elapsed: TimeInterval) {
        let reachable = WCSession.default.isReachable
            print("WATCH SEND hr=\(hr) km=\(distanceKm) elapsed=\(elapsed) reachable=\(reachable)")

        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["type": "update", "hr": hr, "dist": distanceKm, "elapsed": elapsed],
            replyHandler: nil, errorHandler: { _ in })
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { self.state = activationState }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }
}

