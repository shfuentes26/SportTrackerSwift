//  WorkoutInbox.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/28/25.
//
import Foundation

/// Guarda y lista los workouts recibidos desde el Watch (archivos JSON).
final class WorkoutInbox: ObservableObject {
    static let shared = WorkoutInbox()

    @Published private(set) var items: [WorkoutPayload] = []

    private let folder: URL = {
        let base = try! FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: true)
        let dir = base.appendingPathComponent("WorkoutInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func destinationURL(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    /// Mueve el archivo recibido al inbox y actualiza la memoria
    func store(payload: WorkoutPayload, from tempURL: URL) {
        let dest = destinationURL(for: payload.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
        } catch {
            // fallback: copia
            try? FileManager.default.copyItem(at: tempURL, to: dest)
        }
        print("[INBOX] saved:", dest.lastPathComponent)   // 👈 añadido
        upsert(payload)
    }

    func upsert(_ payload: WorkoutPayload) {
        if let i = items.firstIndex(where: { $0.id == payload.id }) {
            items[i] = payload
        } else {
            items.insert(payload, at: 0)
        }
    }

    /// Relee del disco (útil al abrir la app)
    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                 includingPropertiesForKeys: nil)) ?? []
        var loaded: [WorkoutPayload] = []
        for u in urls where u.pathExtension.lowercased() == "json" {
            if let p = try? WorkoutPayloadIO.read(from: u) { loaded.append(p) }
        }
        loaded.sort { $0.start > $1.start }
        items = loaded
    }
}

