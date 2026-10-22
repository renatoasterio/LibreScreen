// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// The pill shown while recording: pulsing dot, timer, pause and stop.
@MainActor
final class RecordingHUDPanelController {
    private var panel: FloatingPanel?

    func show(for source: CaptureSource, recording: RecordingViewModel) {
        hide()
        let panel = FloatingPanel(content: RecordingHUDView(recording: recording), level: .statusBar)
        let screen = source.displayInfo.flatMap { NSScreen.screen(for: $0.id) }
        panel.place(on: screen, anchorX: 0.5, anchorY: 0, margin: 28)
        panel.fadeIn()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct RecordingHUDView: View {
    let recording: RecordingViewModel

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            PulsingDot(isPaused: recording.phase == .paused)
            Text(recording.elapsed.recordingClock)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .accessibilityLabel(Text("Tempo gravado \(recording.elapsed.recordingClock)"))
            if recording.microphoneLevel > 0 {
                LevelMeter(level: recording.microphoneLevel)
            }
            Divider()
                .frame(height: 18)
            HUDButton(
                symbol: recording.phase == .paused ? "play.fill" : "pause.fill",
                label: recording.phase == .paused ? "Retomar" : "Pausar"
            ) {
                Task { await recording.togglePause() }
            }
            HUDButton(symbol: "stop.fill", label: "Parar", tint: DesignTokens.recordRed) {
                Task { await recording.stop() }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm + 2)
        .glassSurface(in: Capsule())
        .padding(8)
    }
}

private struct PulsingDot: View {
    let isPaused: Bool
    @State private var isBright = true

    var body: some View {
        Circle()
            .fill(isPaused ? Color.orange : DesignTokens.recordRed)
            .frame(width: 10, height: 10)
            .opacity(isPaused || isBright ? 1 : 0.35)
            .animation(isPaused ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isBright)
            .onAppear { isBright = false }
            .accessibilityHidden(true)
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Float(index) / 5 < level ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: 6 + CGFloat(index) * 2)
            }
        }
        .accessibilityLabel("Nível do microfone")
        .accessibilityValue(Text("\(Int(level * 100)) por cento"))
    }
}

struct HUDButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var tint: Color = .primary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(isHovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
