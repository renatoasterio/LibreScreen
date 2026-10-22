// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// The draggable webcam preview. Its on-screen frame mirrors `CameraOverlaySettings.overlayRect` for the
/// chosen capture target, so what the user sees is what the compositor draws into the file.
@MainActor
final class CameraBubbleController {
    static let shadowPadding: CGFloat = 24

    private var panel: FloatingPanel?
    private var dragView: DraggableContainerView?
    /// Called with the corner the bubble was released closest to.
    var onCornerChange: (@MainActor (OverlayCorner) -> Void)?

    private(set) var targetRect: CGRect = .zero

    func show(source: any CameraFrameSource, settings: CameraOverlaySettings, targetRect: CGRect) {
        self.targetRect = targetRect
        let side = settings.overlayRect(in: targetRect.size).width
        let view = CameraBubbleView(source: source, settings: settings, side: side)
        if let panel, let dragView {
            dragView.replaceContent(view)
            panel.setContentSize(dragView.fittingSize)
        } else {
            let dragView = DraggableContainerView(content: view)
            dragView.onDragEnded = { [weak self] frame in self?.snap(frame) }
            let panel = FloatingPanel(content: EmptyView(), level: .floating, movable: false)
            panel.contentView = dragView
            panel.setContentSize(dragView.fittingSize)
            panel.orderFrontRegardless()
            self.panel = panel
            self.dragView = dragView
        }
        move(to: settings, animated: false)
    }

    func update(settings: CameraOverlaySettings, targetRect: CGRect) {
        self.targetRect = targetRect
        move(to: settings, animated: true)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        dragView = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Converts the overlay rect (top-left based, inside the target) to an AppKit window frame.
    private func move(to settings: CameraOverlaySettings, animated: Bool) {
        guard let panel else { return }
        let overlay = settings.overlayRect(in: targetRect.size)
        let padding = Self.shadowPadding
        let frame = NSRect(
            x: targetRect.minX + overlay.minX - padding,
            y: targetRect.maxY - overlay.maxY - padding,
            width: overlay.width + padding * 2,
            height: overlay.height + padding * 2
        )
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func snap(_ frame: NSRect) {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let left = centre.x < targetRect.midX
        let top = centre.y > targetRect.midY
        let corner: OverlayCorner = switch (top, left) {
        case (true, true): .topLeft
        case (true, false): .topRight
        case (false, true): .bottomLeft
        case (false, false): .bottomRight
        }
        onCornerChange?(corner)
    }
}

/// Camera preview with the same border and shadow the compositor draws.
struct CameraBubbleView: View {
    let source: any CameraFrameSource
    let settings: CameraOverlaySettings
    let side: CGFloat

    var body: some View {
        CameraPreviewView(source: source, shape: settings.shape)
            .frame(width: max(side, 1), height: max(side, 1))
            .overlay {
                if settings.showsBorder {
                    bubbleShape.stroke(Color.white.opacity(0.85), lineWidth: max(2, side * 0.014))
                }
            }
            .shadow(color: .black.opacity(settings.showsShadow ? 0.45 : 0), radius: side * 0.08, y: side * 0.03)
            .padding(CameraBubbleController.shadowPadding)
            .accessibilityLabel("Pré-visualização da câmera")
            .accessibilityHint("Arraste para um canto da tela para mudar a posição no vídeo")
    }

    private var bubbleShape: AnyShape {
        switch settings.shape {
        case .circle: AnyShape(Circle())
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: settings.cornerRadius(forSide: 100), style: .continuous))
        }
    }
}

/// Hosts SwiftUI content and moves its window while the user drags; reports the final frame.
@MainActor
final class DraggableContainerView: NSView {
    var onDragEnded: (@MainActor (NSRect) -> Void)?
    private var hosting: NSHostingView<AnyView>
    private var dragOffset: NSPoint = .zero

    init(content: some View) {
        hosting = NSHostingView(rootView: AnyView(content))
        super.init(frame: .zero)
        addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func replaceContent(_ content: some View) {
        hosting.rootView = AnyView(content)
    }

    override var fittingSize: NSSize {
        hosting.fittingSize
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let location = window.convertPoint(toScreen: event.locationInWindow)
        dragOffset = NSPoint(x: location.x - window.frame.minX, y: location.y - window.frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let location = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: location.x - dragOffset.x, y: location.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else { return }
        onDragEnded?(window.frame)
    }
}
