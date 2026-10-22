// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// A borderless, non-activating panel that floats above everything, joins every Space and is never
/// captured (`sharingType = .none`). Base for the HUD, countdown, camera bubble and thumbnail panels.
@MainActor
final class FloatingPanel: NSPanel {
    init(content: some View, level: NSWindow.Level = .floating, movable: Bool = true) {
        let hosting = NSHostingController(rootView: content)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        contentViewController = hosting
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .none
        isMovableByWindowBackground = movable
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = true
        setContentSize(hosting.view.fittingSize)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Places the panel at a normalized position inside a screen's visible frame (0,0 = bottom-left).
    func place(on screen: NSScreen?, anchorX: CGFloat, anchorY: CGFloat, margin: CGFloat) {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let target else { return }
        let frame = target.visibleFrame
        let size = self.frame.size
        let x = frame.minX + margin + (frame.width - size.width - margin * 2) * anchorX
        let y = frame.minY + margin + (frame.height - size.height - margin * 2) * anchorY
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    func fadeIn() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func fadeOut(completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
                completion?()
            }
        }
    }
}
