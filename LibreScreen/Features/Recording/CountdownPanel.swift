// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Big number in a glass circle, centred on the display about to be recorded, with a cancel button.
@MainActor
final class CountdownPanelController {
    private var panel: FloatingPanel?
    private let model = CountdownModel()

    func show(_ seconds: Int, on display: DisplayInfo?, cancel: @escaping @MainActor () -> Void) {
        model.seconds = seconds
        model.cancel = cancel
        if panel == nil {
            let panel = FloatingPanel(content: CountdownView(model: model), level: .statusBar, movable: false)
            let screen = display.flatMap { NSScreen.screen(for: $0.id) }
            panel.place(on: screen, anchorX: 0.5, anchorY: 0.5, margin: 0)
            panel.fadeIn()
            self.panel = panel
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

@MainActor
@Observable
final class CountdownModel {
    var seconds = 3
    var cancel: (@MainActor () -> Void)?
}

private struct CountdownView: View {
    let model: CountdownModel

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("\(model.seconds)")
                .font(.system(size: 88, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: model.seconds)
                .frame(width: 180, height: 180)
                .glassSurface(in: Circle())
                .accessibilityLabel(Text("A gravação começa em \(model.seconds) segundos"))
            Button("Cancelar") {
                model.cancel?()
            }
            .glassButtonStyle()
            .controlSize(.large)
        }
        .padding(DesignTokens.Spacing.xl)
    }
}
