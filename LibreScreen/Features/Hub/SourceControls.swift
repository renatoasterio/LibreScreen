// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Contextual controls under the source cards: display menu, window chooser or region button.
struct SourceControls: View {
    @Bindable var hub: HubViewModel

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            switch hub.sourceKind {
            case .display:
                displayControls
            case .window:
                windowControls
            case .region:
                regionControls
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .animation(.snappy(duration: 0.2), value: hub.sourceKind)
    }

    @ViewBuilder
    private var displayControls: some View {
        if hub.displays.count > 1 {
            Picker(selection: $hub.selectedDisplayID) {
                ForEach(hub.displays) { display in
                    Text(label(for: display)).tag(Optional(display.id))
                }
            } label: {
                Label("Monitor", systemImage: "display.2")
            }
            .pickerStyle(.menu)
            .fixedSize()
        } else {
            Label(hub.selectedDisplay.map(label(for:)) ?? String(localized: "Nenhum monitor encontrado"), systemImage: "display")
                .foregroundStyle(.secondary)
        }
    }

    private var windowControls: some View {
        Button {
            hub.chooseWindow()
        } label: {
            Label(hub.selectedWindow?.displayTitle ?? String(localized: "Escolher janela…"), systemImage: "macwindow")
                .lineLimit(1)
        }
        .glassButtonStyle()
        .help("Escolhe a janela que será capturada")
    }

    private var regionControls: some View {
        Button {
            Task { await hub.selectRegion() }
        } label: {
            Label(regionTitle, systemImage: "rectangle.dashed")
        }
        .glassButtonStyle()
        .help("Desenha a área da tela que será capturada")
    }

    private var regionTitle: String {
        if let region = hub.selectedRegion {
            return String(localized: "Área de \(Int(region.rect.width))×\(Int(region.rect.height)) pt")
        }
        return String(localized: "Selecionar área…")
    }

    private func label(for display: DisplayInfo) -> String {
        let size = "\(Int(display.frame.width))×\(Int(display.frame.height))"
        return display.isMain ? String(localized: "\(display.name) · \(size) · principal") : "\(display.name) · \(size)"
    }
}
