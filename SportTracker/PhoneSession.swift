//
//  PhoneSession.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/27/25.
//
import Foundation
import WatchConnectivity
import SwiftData
import HealthKit

final class PhoneSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneSession()
    @Published var lastReceivedSummary: String = "—"

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // 1) Con replyHandler
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        handle(message: message, replyHandler: replyHandler)
    }

    // 2) SIN replyHandler
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
                 error: Error?) {
        print("[WC][iOS] activationDidComplete: \(activationState.rawValue) error: \(String(describing: error))")
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handle(message: userInfo, replyHandler: nil)
    }
    
    // MARK: - Guardado en SwiftData desde payload del Watch
    @MainActor
    private func saveWatchRunning(payload: WorkoutPayload, polyline: String?) {
        guard let container = Persistence.shared.appContainer else {
            print("[SwiftData] container missing")
            return
        }
        let context = container.mainContext

        // 1) Crea la RunningSession base (no rompe tu flujo actual)
        let session = RunningSession(
            date: payload.start,
            durationSeconds: Int(payload.duration),
            distanceMeters: payload.distanceMeters ?? 0,
            notes: "Imported from Apple Watch",
            routePolyline: polyline
        )
        context.insert(session)

        // 2) Crea detalle y enlaza
        let detail = RunningWatchDetail()
        detail.session = session
        context.insert(detail)

        // HR series
        if let hrs = payload.hrSeries {
            for s in hrs {
                let p = WatchHRPoint(t: s.t, v: s.v)
                p.detail = detail
                context.insert(p)
                detail.hrPoints.append(p)
            }
        }

        // Pace series (m/s)
        if let paces = payload.paceSeries {
            for s in paces {
                let p = WatchPacePoint(t: s.t, v: s.v)
                p.detail = detail
                context.insert(p)
                detail.pacePoints.append(p)
            }
        }

        // Elevación (cuando llegue en el payload)
        // Elevación (si viene en el payload)
        if let elev = payload.elevationSeries {
            for s in elev {
                let p = WatchElevationPoint(t: s.t, v: s.v) // modelo igual que HR/Pace
                p.detail = detail
                context.insert(p)
                detail.elevationPoints.append(p)
            }
        }
        
        // Splits por km
        if let splits = payload.kmSplits {
            for sp in splits {
                let e = RunningWatchSplit(index: sp.index,
                                          startOffset: sp.startOffset,
                                          endOffset: sp.endOffset,
                                          duration: sp.duration,
                                          distanceMeters: sp.distanceMeters,
                                          avgHR: sp.avgHR,
                                          avgSpeed: sp.avgSpeed)
                e.detail = detail
                context.insert(e)
                detail.splits.append(e)
            }
        }

        do {
            try context.save()
            Task { @MainActor in
                // Rellena routePolyline en las sesiones que no la tengan (incluida la que acabas de crear)
                _ = try? await HealthKitImportService.backfillMissingRoutes(
                    context: Persistence.shared.appContainer!.mainContext,
                    limit: 1   // basta con 1 run reciente
                )
            }
            print("[SwiftData] Saved RunningSession + Watch detail")
        } catch {
            print("[SwiftData][ERROR] save:", error)
        }
    }

    // MARK: - Archivos desde el Watch (transferFile)
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let meta = file.metadata ?? [:]
        print("[WC][iOS] didReceive file: \(file.fileURL.lastPathComponent), meta:", meta)

        do {
            let payload = try WorkoutPayloadIO.read(from: file.fileURL)
            // (opcional) seguimos guardando el JSON en el Inbox para debug
            WorkoutInbox.shared.store(payload: payload, from: file.fileURL)

            // ⬇️ Guarda también en SwiftData
            let poly = meta["routePolyline"] as? String
            Task { @MainActor in
                self.saveWatchRunning(payload: payload, polyline: poly)
            }
            DispatchQueue.main.async {
                self.lastReceivedSummary = String(
                    format: "Workout %@ • %.2f km • %d splits",
                    payload.id.uuidString.prefix(6) as CVarArg,
                    (payload.distanceMeters ?? 0)/1000.0,
                    payload.kmSplits?.count ?? 0
                )
            }
        } catch {
            print("[WC][iOS][ERROR] decoding workout:", error)
        }
    }
}
