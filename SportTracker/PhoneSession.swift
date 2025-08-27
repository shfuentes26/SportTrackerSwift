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

    // 1) Con replyHandler (ya lo tenías)
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        handle(message: message, replyHandler: replyHandler)
    }

    // 2) SIN replyHandler (faltaba)
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any]) {
        handle(message: message, replyHandler: nil)
    }

    // Lógica común
    private func handle(message: [String: Any],
                        replyHandler: (([String : Any]) -> Void)?) {
        if let type = message["type"] as? String, type == "update" {
            let hr = message["hr"] as? Int ?? 0
            let km = message["dist"] as? Double ?? 0
            let el = message["elapsed"] as? Double ?? 0

            print("IPHONE RECV update hr=\(hr) km=\(km) elapsed=\(el)")

            DispatchQueue.main.async {
                LiveWorkoutBridge.shared.hr = hr
                LiveWorkoutBridge.shared.km = km
                LiveWorkoutBridge.shared.elapsed = el
                LiveWorkoutBridge.shared.isRunning = true
            }
            replyHandler?(["ok": true])
            return
        }
        
        if let type = message["type"] as? String, type == "summary" {
            let start = Date(timeIntervalSince1970: message["start"] as? Double ?? 0)
            let end   = Date(timeIntervalSince1970: message["end"] as? Double ?? 0)
            let km    = message["dist"] as? Double ?? 0
            let avgHR = message["avgHR"] as? Int ?? 0

            print("IPHONE RECV summary km=\(km) avgHR=\(avgHR)")

            DispatchQueue.main.async {
                LiveWorkoutBridge.shared.lastSummary = WorkoutSummary(
                    start: start, end: end, distanceKm: km, avgHR: avgHR
                )
                LiveWorkoutBridge.shared.isRunning = false
            }
            replyHandler?(["ok": true])
            return
        }
        if let type = message["type"] as? String, type == "state" {
            if (message["value"] as? String) == "stopped" {
                DispatchQueue.main.async {
                    LiveWorkoutBridge.shared.isRunning = false
                }
            } else if (message["value"] as? String) == "started" {
                DispatchQueue.main.async {
                    LiveWorkoutBridge.shared.isRunning = true
                    LiveWorkoutBridge.shared.hr = 0
                    LiveWorkoutBridge.shared.km = 0
                    LiveWorkoutBridge.shared.elapsed = 0
                }
            }
            replyHandler?(["ok": true])
            return
        }

        if message["ping"] != nil {
            replyHandler?(["pong": "hello-from-iphone"])
            return
        }

        replyHandler?(["ok": true])
    }

    // Requeridos mínimos
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
    
    // Cuando el iPhone no está en foreground, el watch enviará con transferUserInfo.
    // Este callback llega aunque la app esté en background.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handle(message: userInfo, replyHandler: nil)
    }
}
