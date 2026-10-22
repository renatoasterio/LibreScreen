// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Main-menu commands; in-app shortcuts mirror the hub, global ones are in Settings › Atalhos.
struct AppCommands: Commands {
    let container: AppContainer

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Captura") {
            Button("Gravar tela inteira") { quick(.record, .display) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Button("Gravar janela…") { quick(.record, .window) }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            Button("Gravar área…") { quick(.record, .region) }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            Divider()
            Button("Capturar tela inteira") { quick(.screenshot, .display) }
                .keyboardShortcut("4", modifiers: [.command, .shift])
            Button("Capturar janela…") { quick(.screenshot, .window) }
                .keyboardShortcut("5", modifiers: [.command, .shift])
            Button("Capturar área…") { quick(.screenshot, .region) }
                .keyboardShortcut("6", modifiers: [.command, .shift])
            Divider()
            Button(container.recording.phase == .paused ? "Retomar gravação" : "Pausar gravação") {
                Task { await container.recording.togglePause() }
            }
            .disabled(!container.recording.isRecordingOrPaused)
            Button("Parar gravação") {
                Task { await container.recording.stop() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!container.recording.isRecordingOrPaused)
        }
        CommandGroup(after: .windowList) {
            Button("Mostrar LibreScreen") { container.windows.showHub() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }

    private func quick(_ mode: HubViewModel.Mode, _ kind: SourceKind) {
        Task { await container.hub.quickAction(mode: mode, kind: kind) }
    }
}
