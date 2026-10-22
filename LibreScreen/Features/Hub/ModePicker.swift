// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Glass pill with a sliding indicator: Record | Capture.
struct ModePicker: View {
    @Binding var selection: HubViewModel.Mode
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HubViewModel.Mode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = mode
                    }
                } label: {
                    Label(title(for: mode), systemImage: icon(for: mode))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == mode ? Color.white : Color.primary)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? [.isSelected] : [])
            }
        }
        .padding(3)
        .glassSurface(in: Capsule())
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modo")
    }

    private func title(for mode: HubViewModel.Mode) -> String {
        switch mode {
        case .record: String(localized: "Gravar")
        case .screenshot: String(localized: "Capturar")
        }
    }

    private func icon(for mode: HubViewModel.Mode) -> String {
        switch mode {
        case .record: "record.circle"
        case .screenshot: "camera.viewfinder"
        }
    }
}

/// Three cards: full display, window, region.
struct SourceKindPicker: View {
    @Binding var selection: SourceKind

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ForEach(SourceKind.allCases) { kind in
                SourceKindCard(kind: kind, isSelected: selection == kind) {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = kind
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fonte da captura")
    }
}

private struct SourceKindCard: View {
    let kind: SourceKind
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 32)
                Text(title)
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: DesignTokens.Radius.lg, tint: isSelected ? Color.accentColor : nil, interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
        }
        .scaleEffect(isHovering && !isSelected ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var icon: String {
        switch kind {
        case .display: "display"
        case .window: "macwindow"
        case .region: "rectangle.dashed"
        }
    }

    private var title: String {
        switch kind {
        case .display: String(localized: "Tela inteira")
        case .window: String(localized: "Janela")
        case .region: String(localized: "Área")
        }
    }
}
