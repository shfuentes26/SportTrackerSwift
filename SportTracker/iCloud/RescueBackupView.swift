//
//  RescueBackupView.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/4/25.
//
// RescueBackupView.swift (colócala donde quieras)
import SwiftUI

struct RescueBackupView: View {
    @StateObject private var vm = BackupViewModel()

    var body: some View {
        NavigationView {
            Form {
                Section("iCloud (Rescate)") {
                    Button {
                        vm.makeBackup()
                    } label: {
                        if vm.isWorking { ProgressView() }
                        else { Text("Hacer copia de Application Support") }
                    }

                    Button("Actualizar lista") { vm.refreshList() }

                    if !vm.backups.isEmpty {
                        ForEach(vm.backups, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent).lineLimit(1)
                                Spacer()
                                Button(role: .destructive) { vm.deleteBackup(url) } label: { Text("Borrar") }
                            }
                        }
                    }

                    if let msg = vm.lastResult {
                        Text(msg).font(.footnote)
                    }
                }
            }
            .navigationTitle("Rescue")
            .onAppear { vm.refreshList() }
        }
    }
}

