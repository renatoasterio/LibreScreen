// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Quick actions in the menu bar. Mirrors the hub so the window is optional.
struct MenuBarMenuView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Abrir LibreScreen") {
            container.windows.showHub()
        }
        Divider()
        if container.recording.isRecordingOrPaused {
            Button("Parar gravação") { Task { await container.recording.stop() } }
            Button(container.recording.phase == .paused ? "Retomar gravação" : "Pausar gravação") {
                Task { await container.recording.togglePause() }
            }
        } else {
            Button("Gravar tela inteira") { quick(.record, .display) }
            Button("Gravar janela…") { quick(.record, .window) }
            Button("Gravar área…") { quick(.record, .region) }
            Divider()
            Button("Capturar tela") { quick(.screenshot, .display) }
            Button("Capturar janela…") { quick(.screenshot, .window) }
            Button("Capturar área…") { quick(.screenshot, .region) }
        }
        Divider()
        Button("Configurações…") {
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Sair do LibreScreen") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func quick(_ mode: HubViewModel.Mode, _ kind: SourceKind) {
        Task { await container.hub.quickAction(mode: mode, kind: kind) }
    }
}

/// The status item icon; shows the timer while recording.
struct MenuBarLabel: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        if container.recording.isRecordingOrPaused {
            Label(container.recording.elapsed.recordingClock, systemImage: "record.circle.fill")
                .labelStyle(.titleAndIcon)
                .accessibilityLabel(Text("LibreScreen gravando, \(container.recording.elapsed.recordingClock)"))
        } else {
            Image(systemName: "record.circle")
                .accessibilityLabel("LibreScreen")
        }
    }
}
