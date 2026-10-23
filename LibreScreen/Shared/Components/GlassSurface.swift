// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Liquid Glass on macOS 26, a translucent material with a hairline border on macOS 15.
/// The only place in the app that branches on the OS version for surfaces.
///
/// `tint` is drawn as a light wash over plain glass rather than through `Glass.tint`: a tinted glass
/// becomes a saturated accent-coloured slab on macOS 26/27, which hid accent-coloured text and icons.
struct GlassSurface<S: Shape>: ViewModifier {
    static var tintOpacity: Double {
        0.16
    }

    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background(wash)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(wash)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    private var wash: some View {
        shape.fill(tint?.opacity(Self.tintOpacity) ?? Color.clear)
    }
}

extension View {
    func glassSurface(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    func glassSurface(cornerRadius: CGFloat = DesignTokens.Radius.lg, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// `.glassProminent` on macOS 26, `.borderedProminent` before.
    @ViewBuilder
    func prominentGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// `.glass` on macOS 26, `.bordered` before.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
