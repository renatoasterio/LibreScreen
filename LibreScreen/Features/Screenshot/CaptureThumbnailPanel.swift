// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// The small preview that slides into the bottom-right corner after a capture, like the system's.
@MainActor
final class CaptureThumbnailPanelController {
    static let autoDismissDelay: Duration = .seconds(7)

    private var panel: FloatingPanel?
    private var dismissTask: Task<Void, Never>?
    private let model = ThumbnailPanelModel()
    private let thumbnails: ThumbnailLoader
    private let captures: any CaptureStoring

    /// Opens the item; defaults to the system handler when unset.
    var onOpen: (@MainActor (CaptureItem) -> Void)?
    var onRemoved: (@MainActor (CaptureItem) -> Void)?

    init(thumbnails: ThumbnailLoader, captures: any CaptureStoring) {
        self.thumbnails = thumbnails
        self.captures = captures
    }

    func show(_ item: CaptureItem) {
        hide()
        model.item = item
        model.image = nil
        model.isHovering = false
        model.actions = ThumbnailPanelActions(
            open: { [weak self] in self?.open(item) },
            reveal: { CaptureItemActions.revealInFinder(item) },
            copy: { CaptureItemActions.copy(item) },
            delete: { [weak self] in self?.delete(item) }
        )
        model.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }
        let panel = FloatingPanel(content: CaptureThumbnailView(model: model), level: .statusBar, movable: false)
        panel.place(on: NSScreen.main, anchorX: 1, anchorY: 0, margin: 20)
        panel.fadeIn()
        self.panel = panel
        Task { [weak self, model, thumbnails] in
            let image = await thumbnails.thumbnail(for: item)
            guard self?.model.item?.id == item.id else { return }
            model.image = image
        }
        scheduleDismiss()
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func open(_ item: CaptureItem) {
        hide()
        if let onOpen {
            onOpen(item)
        } else {
            CaptureItemActions.open(item)
        }
    }

    private func delete(_ item: CaptureItem) {
        hide()
        Task { [captures, onRemoved] in
            try? await captures.remove(item.id, deletingFile: true)
            onRemoved?(item)
        }
    }

    private func hoverChanged(_ hovering: Bool) {
        if hovering {
            dismissTask?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoDismissDelay)
            guard !Task.isCancelled else { return }
            self?.panel?.fadeOut { [weak self] in self?.panel = nil }
        }
    }
}

struct ThumbnailPanelActions {
    let open: @MainActor () -> Void
    let reveal: @MainActor () -> Void
    let copy: @MainActor () -> Void
    let delete: @MainActor () -> Void
}

@MainActor
@Observable
final class ThumbnailPanelModel {
    var item: CaptureItem?
    var image: CGImage?
    var isHovering = false
    var actions: ThumbnailPanelActions?
    var onHoverChange: (@MainActor (Bool) -> Void)?
}

private struct CaptureThumbnailView: View {
    let model: ThumbnailPanelModel

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ZStack(alignment: .bottomTrailing) {
                thumbnail
                if let duration = model.item?.duration {
                    Text(duration.recordingClock)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .frame(width: 236, height: 148)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .onTapGesture { model.actions?.open() }

            HStack(spacing: DesignTokens.Spacing.sm) {
                HUDButton(symbol: model.item?.kind == .screenshot ? "pencil.and.outline" : "play.fill", label: "Abrir") {
                    model.actions?.open()
                }
                HUDButton(symbol: "folder", label: "Mostrar no Finder") { model.actions?.reveal() }
                HUDButton(symbol: "doc.on.doc", label: "Copiar") { model.actions?.copy() }
                HUDButton(symbol: "trash", label: "Apagar", tint: DesignTokens.recordRed) { model.actions?.delete() }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .glassSurface(cornerRadius: DesignTokens.Radius.lg)
        .padding(10)
        .onHover { hovering in
            model.isHovering = hovering
            model.onHoverChange?(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.item?.kind == .screenshot ? "Captura de tela salva" : "Gravação salva")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = model.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay { ProgressView().controlSize(.small) }
        }
    }
}
