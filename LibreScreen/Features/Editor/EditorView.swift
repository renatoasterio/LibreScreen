// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Toolbar + canvas + status bar of the annotation editor.
struct EditorView: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model)
            Divider()
            GeometryReader { proxy in
                AnnotationCanvasView(model: model)
                    .onAppear { model.fitZoom(in: proxy.size) }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var statusBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Text("\(Int(model.document.visibleRect.width)) × \(Int(model.document.visibleRect.height)) px")
                .monospacedDigit()
            if model.document.cropRect != nil {
                Button("Desfazer recorte") { model.resetCrop() }
                    .buttonStyle(.link)
            }
            Spacer()
            if let message = model.statusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Slider(value: $model.zoom, in: 0.1 ... 4) {
                Text("Zoom")
            }
            .frame(width: 140)
            Text("\(Int(model.zoom * 100))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

/// Tools on the left, style in the middle, actions on the right.
struct EditorToolbar: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            toolPalette
            Divider().frame(height: 22)
            colorSwatches
            strokeMenu
            if model.tool == .text {
                fontSizeMenu
            }
            if model.tool == .rectangle || model.tool == .ellipse {
                Toggle("Preencher", isOn: $model.style.isFilled)
                    .toggleStyle(.checkbox)
            }
            Spacer()
            if model.tool == .crop, model.cropDraft != nil {
                Button("Aplicar recorte") { model.applyCrop() }
                    .prominentGlassButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
            historyButtons
            Divider().frame(height: 22)
            actionButtons
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.bar)
    }

    private var toolPalette: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: Self.symbol(for: tool))
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(model.tool == tool ? Color.accentColor.opacity(0.22) : Color.clear)
                        )
                        .foregroundStyle(model.tool == tool ? Color.accentColor : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Self.title(for: tool))
                .accessibilityLabel(Self.title(for: tool))
                .accessibilityAddTraits(model.tool == tool ? [.isSelected] : [])
                .keyboardShortcut(Self.shortcut(for: tool), modifiers: [])
            }
        }
        .padding(3)
        .glassSurface(cornerRadius: 10)
    }

    private var colorSwatches: some View {
        HStack(spacing: 5) {
            ForEach(RGBAColor.presets, id: \.self) { preset in
                Button {
                    model.style.color = preset
                } label: {
                    Circle()
                        .fill(Color(cgColor: AnnotationRenderer.cgColor(preset)))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .overlay {
                            if model.style.color == preset {
                                Circle().stroke(Color.accentColor, lineWidth: 2).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cor")
            }
            ColorPicker(selection: pickerColor, supportsOpacity: true) { Text("Cor personalizada") }
                .labelsHidden()
                .frame(width: 24)
        }
    }

    private var pickerColor: Binding<Color> {
        Binding(
            get: { Color(cgColor: AnnotationRenderer.cgColor(model.style.color)) },
            set: { newValue in
                let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                guard
                    let converted = newValue.cgColor?.converted(to: space, intent: .defaultIntent, options: nil),
                    let parts = converted.components, parts.count >= 3 else { return }
                model.style.color = RGBAColor(red: parts[0], green: parts[1], blue: parts[2], alpha: parts.count > 3 ? parts[3] : 1)
            }
        )
    }

    private var strokeMenu: some View {
        Menu {
            ForEach(AnnotationStyle.lineWidths, id: \.self) { width in
                Button {
                    model.style.lineWidth = width
                } label: {
                    Label("\(Int(width)) pt", systemImage: model.style.lineWidth == width ? "checkmark" : "")
                }
            }
        } label: {
            Label("\(Int(model.style.lineWidth)) pt", systemImage: "lineweight")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Espessura do traço")
    }

    private var fontSizeMenu: some View {
        Menu {
            ForEach(AnnotationStyle.fontSizes, id: \.self) { size in
                Button("\(Int(size)) pt") { model.style.fontSize = size }
            }
        } label: {
            Label("\(Int(model.style.fontSize)) pt", systemImage: "textformat.size")
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private var historyButtons: some View {
        HStack(spacing: 4) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.undoManager.canUndo)
                .help("Desfazer")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.undoManager.canRedo)
                .help("Refazer")
            Button(role: .destructive) { model.deleteSelection() } label: { Image(systemName: "trash") }
                .disabled(model.selectedID == nil)
                .help("Apagar marcação selecionada")
        }
        .buttonStyle(.borderless)
    }

    private var actionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                model.copyToClipboard()
            } label: {
                Label("Copiar", systemImage: "doc.on.doc")
            }
            .glassButtonStyle()
            .keyboardShortcut("c", modifiers: [.command, .shift])
            ShareButton(model: model)
            Button {
                do {
                    try model.save()
                } catch {
                    model.statusMessage = error.localizedDescription
                }
            } label: {
                Label("Salvar", systemImage: "square.and.arrow.down")
            }
            .prominentGlassButtonStyle()
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    static func symbol(for tool: AnnotationTool) -> String {
        switch tool {
        case .select: "arrow.up.left"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .freehand: "pencil.tip"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .pixelate: "mosaic"
        case .number: "1.circle"
        case .crop: "crop"
        }
    }

    static func title(for tool: AnnotationTool) -> String {
        switch tool {
        case .select: String(localized: "Selecionar (V)")
        case .arrow: String(localized: "Seta (A)")
        case .line: String(localized: "Linha (L)")
        case .rectangle: String(localized: "Retângulo (R)")
        case .ellipse: String(localized: "Elipse (O)")
        case .freehand: String(localized: "Caneta (P)")
        case .text: String(localized: "Texto (T)")
        case .highlighter: String(localized: "Marca-texto (H)")
        case .pixelate: String(localized: "Pixelizar (M)")
        case .number: String(localized: "Numeração (N)")
        case .crop: String(localized: "Recortar (C)")
        }
    }

    static func shortcut(for tool: AnnotationTool) -> KeyEquivalent {
        switch tool {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .freehand: "p"
        case .text: "t"
        case .highlighter: "h"
        case .pixelate: "m"
        case .number: "n"
        case .crop: "c"
        }
    }
}

/// `NSSharingServicePicker` needs an AppKit anchor, so the Share button is a real `NSButton`.
struct ShareButton: NSViewRepresentable {
    let model: EditorViewModel

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: String(localized: "Compartilhar"),
            target: context.coordinator,
            action: #selector(Coordinator.share(_:))
        )
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.model = model
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject {
        var model: EditorViewModel

        init(model: EditorViewModel) {
            self.model = model
        }

        @objc func share(_ sender: NSButton) {
            guard let image = model.renderedImage() else { return }
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            let picker = NSSharingServicePicker(items: [nsImage])
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
