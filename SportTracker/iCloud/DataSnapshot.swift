//
//  DataSnapshot.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/4/25.
//

import Foundation

/// En esta versión “rescate” NO serializamos entidades una a una.
/// En su lugar, copiamos la **carpeta Application Support** completa (donde vive el store de SwiftData).
/// Esto preserva los ficheros .sqlite / -wal / -shm y cualquier otro recurso de soporte.

enum LocalStoreBackup {
    /// Devuelve la carpeta **Application Support** de la sandbox de la app.
    static func applicationSupportDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "LocalStoreBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Application Support directory"])
        }
        return url
    }

    /// Crea una copia de Application Support en iCloud Drive (Backups/AS-YYYYMMDD-HHmmss)
    /// Devuelve la URL del backup en iCloud Drive.
    @discardableResult
    static func exportRawAppSupportToICloud() throws -> URL {
        let asURL = try applicationSupportDirectory()

        // Nombre de carpeta con marca temporal
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let name = "AS-\(stamp.string(from: Date()))"

        return try ICloudBackupService.copyDirectoryToBackup(named: name, from: asURL)
    }
}
