//
//  BackupViewModel.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/4/25.
//
import Foundation

@MainActor
final class BackupViewModel: ObservableObject {
    @Published var isWorking = false
    @Published var lastResult: String? = nil
    @Published var backups: [URL] = []

    func refreshList() {
        do {
            backups = try ICloudBackupService.listBackups()
        } catch {
            lastResult = "Error listando copias: \(error.localizedDescription)"
        }
    }

    /// Hace una copia “cruda” del Application Support (incluye store de SwiftData)
    func makeBackup() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let url = try LocalStoreBackup.exportRawAppSupportToICloud()
                lastResult = "Copia creada: \(url.lastPathComponent)"
                refreshList()
            } catch {
                lastResult = "Fallo al crear copia: \(error.localizedDescription)"
            }
        }
    }

    func deleteBackup(_ url: URL) {
        do {
            try ICloudBackupService.deleteBackup(url)
            refreshList()
        } catch {
            lastResult = "No se pudo borrar: \(error.localizedDescription)"
        }
    }
}

