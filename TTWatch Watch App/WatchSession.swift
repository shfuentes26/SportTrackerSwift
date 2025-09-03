import SwiftUI
import WatchConnectivity

final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()

    @Published var lastReply: String = "WC idle"

    // Llamar siempre en App.init y también en onAppear (por si acaso)
    func activate() {
        let supported = WCSession.isSupported()
        let s = WCSession.default
        s.delegate = self
        s.activate() // fuerza activación
        setStatus("WC activating… (supported=\(supported))")
        logState("activate()")
    }

    // Si te muestra state=0, llama a esto para reintentar
    func ensureActivated() {
        let s = WCSession.default
        if s.activationState == .activated {
            logState("ensureActivated:already")
        } else {
            s.activate()
            logState("ensureActivated:activate()")
        }
    }

    func pingPhone() {
        let s = WCSession.default
        guard s.activationState == .activated else {
            setStatus("WC not activated (state=\(s.activationState.rawValue))")
            return
        }
        guard s.isReachable else {
            setStatus("Phone not reachable")
            return
        }
        s.sendMessage(["ping": "watch"], replyHandler: { reply in
            self.setStatus("Reply: \(reply)")
        }, errorHandler: { err in
            self.setStatus("Ping error: \(err.localizedDescription)")
        })
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error { setStatus("WC activate error: \(error.localizedDescription)") }
        else { setStatus("WC activated ✓") }
        logState("activationDidComplete")
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        logState("reachability")
    }

    func session(_ session: WCSession,
                 didFinish fileTransfer: WCSessionFileTransfer,
                 error: Error?) {
        if let error {
            setStatus("Transfer error: \(error.localizedDescription)")
        } else {
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            setStatus("Workout sent ✔︎")
        }
        logState("didFinish")
    }

    // MARK: - Helpers

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.lastReply = text }
    }

    private func logState(_ where_: String) {
        let s = WCSession.default
        // isPaired no existe en watchOS; usamos isCompanionAppInstalled
        let msg = "[WC][watch][\(where_)] state=\(s.activationState.rawValue) " +
                  "installed=\(s.isCompanionAppInstalled) " +
                  "reachable=\(s.isReachable) " +
                  "outstanding=\(s.outstandingFileTransfers.count)"
        print(msg)
        setStatus(msg)
    }
}
