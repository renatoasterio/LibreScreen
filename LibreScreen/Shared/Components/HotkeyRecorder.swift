// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Click, press a combination, done. Uses a local key monitor only while recording and removes it after.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? String(localized: "Pressione as teclas…") : (hotkey?.displayString ?? String(localized: "Nenhum")))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .frame(minWidth: 110)
                    .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
            }
            .glassButtonStyle()
            .accessibilityLabel(isRecording ? "Gravando atalho" : "Atalho atual \(hotkey?.displayString ?? "nenhum")")
            if hotkey != nil, !isRecording {
                Button {
                    hotkey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remover atalho")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels without changing the shortcut.
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let candidate = Hotkey(
                keyCode: event.keyCode,
                modifierFlags: UInt(flags.rawValue),
                keyLabel: KeyLabels.label(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
            )
            guard candidate.isValid else { return nil }
            hotkey = candidate
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
