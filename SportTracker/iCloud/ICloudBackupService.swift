//
//  ICloudBackupService.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/4/25.
//

import Foundation

/// Utilidades de carpeta/archivo en iCloud Drive (Documents › SportTracker › Backups)
struct ICloudBackupService {
    /// ⚠️ Ajusta a tu container real si quieres forzar un contenedor específico.
    /// Si usas "default", deja nil y usará el contenedor por defecto del target.
    static let containerID: String? = nil //"iCloud.com.satcom.sporttracker"

    enum BackupError: Error {
        case icloudUnavailable
        case containerURLMissing
        case cannotCreateFolder
        case sourceNotFound
        case copyFailed(Error)
    }

    /// URL base: iCloud Drive / Documents / SportTracker / Backups
    static var backupsFolderURL: URL? {
        #if targetEnvironment(simulator)
        // En simulador no hay iCloud: usamos Documents para poder probar el flujo.
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        #else
        let base = FileManager.default.url(forUbiquityContainerIdentifier: containerID)
        #endif
        guard let base else { return nil }
        return base
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("SportTracker/Backups", isDirectory: true)
    }

    /// ¿Hay iCloud disponible? (en simulador devolvemos true para poder probar UI)
    static func isAvailable() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return FileManager.default.ubiquityIdentityToken != nil
        #endif
    }

    /// Crea la carpeta Backups si no existe y devuelve su URL
    @discardableResult
    static func ensureBackupsFolder() throws -> URL {
        guard let url = backupsFolderURL else { throw BackupError.containerURLMissing }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Crea una subcarpeta dentro de Backups con el nombre dado y la devuelve.
    static func makeBackupFolder(named name: String) throws -> URL {
        let base = try ensureBackupsFolder()
        let dst = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        return dst
    }

    /// Copia recursivamente una carpeta local a la subcarpeta de Backups.
    /// Devuelve la URL final en iCloud Drive.
    @discardableResult
    static func copyDirectoryToBackup(named backupName: String, from sourceDir: URL) throws -> URL {
        guard isAvailable() else { throw BackupError.icloudUnavailable }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceDir.path, isDirectory: &isDir), isDir.boolValue
        else { throw BackupError.sourceNotFound }

        let dst = try makeBackupFolder(named: backupName)
        try copyDirectoryContents(from: sourceDir, to: dst)
        return dst
    }

    /// Copia recursivamente el contenido de `from` en `to`.
    private static func copyDirectoryContents(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

        for item in items {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            let target = dst.appendingPathComponent(item.lastPathComponent, isDirectory: values.isDirectory ?? false)
            if values.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                try copyDirectoryContents(from: item, to: target)
            } else {
                // Sobrescribe si existe (backup incremental)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    /// Lista los backups (subcarpetas) ordenados por fecha de creación descendente.
    static func listBackups() throws -> [URL] {
        let base = try ensureBackupsFolder()
        let items = try FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let dated: [(URL, Date)] = try items.compactMap {
            let v = try $0.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            guard v.isDirectory == true else { return nil }
            return ($0, v.creationDate ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    /// Borra un backup (carpeta) completo.
    static func deleteBackup(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
