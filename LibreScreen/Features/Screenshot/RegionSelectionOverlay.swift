// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

enum RegionSelectionResult: Sendable, Equatable {
    case region(RegionInfo)
    case window(WindowInfo)
}

/// Lets the user pick a region or a window, like the system's ⌘⇧4: one transparent overlay per
/// display, drag to select, Space toggles window mode, Esc cancels. Implemented by `WindowCoordinator`.
@MainActor
protocol RegionSelecting: AnyObject {
    func selectRegion(displays: [DisplayInfo], windows: [WindowInfo]) async -> RegionSelectionResult?
}

/// Owns the per-display overlay windows for one selection session.
@MainActor
final class RegionSelectionController {
    private var overlays: [RegionSelectionWindow] = []
    private var continuation: CheckedContinuation<RegionSelectionResult?, Never>?

    var isActive: Bool {
        !overlays.isEmpty
    }

    func select(displays: [DisplayInfo], windows: [WindowInfo]) async -> RegionSelectionResult? {
        guard !isActive else { return nil }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let windowRects = windows.filter(\.isOnScreen).map { window in
            (window, CaptureCoordinates.appKitRect(fromGlobal: window.frame, mainDisplayHeight: mainHeight))
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for display in displays {
                guard let screen = NSScreen.screen(for: display.id) else { continue }
                let overlay = RegionSelectionWindow(screen: screen, display: display, windows: windowRects)
                overlay.onFinish = { [weak self] result in self?.finish(with: result) }
                overlays.append(overlay)
                overlay.orderFrontRegardless()
            }
            guard !overlays.isEmpty else { return finish(with: nil) }
            NSApp.activate()
            let mouse = NSEvent.mouseLocation
            let initial = overlays.first { $0.frame.contains(mouse) } ?? overlays[0]
            initial.makeKeyAndOrderFront(nil)
        }
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with result: RegionSelectionResult?) {
        for overlay in overlays {
            overlay.orderOut(nil)
        }
        overlays.removeAll()
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Full-screen transparent window above everything on one display.
@MainActor
final class RegionSelectionWindow: NSWindow {
    var onFinish: (@MainActor (RegionSelectionResult?) -> Void)?

    init(screen: NSScreen, display: DisplayInfo, windows: [(WindowInfo, CGRect)]) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .none
        let localWindows = windows.map { ($0.0, $0.1.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)) }
        let view = RegionSelectionView(display: display, windows: localWindows)
        view.onFinish = { [weak self] result in self?.onFinish?(result) }
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Crosshair, dimming, selection rectangle, size label and window highlighting, drawn with AppKit.
@MainActor
final class RegionSelectionView: NSView {
    private enum Mode {
        case region
        case window
    }

    var onFinish: (@MainActor (RegionSelectionResult?) -> Void)?

    private let display: DisplayInfo
    private let windows: [(WindowInfo, CGRect)]
    private var mode: Mode = .region
    private var cursor: NSPoint?
    private var dragStart: NSPoint?
    private var selection: NSRect?
    private var hovered: (WindowInfo, CGRect)?
    private var trackingArea: NSTrackingArea?

    init(display: DisplayInfo, windows: [(WindowInfo, CGRect)]) {
        self.display = display
        self.windows = windows
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Events

    override func mouseMoved(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        updateHover()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        cursor = point
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        selection = NSRect(
            x: min(dragStart.x, point.x),
            y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x),
            height: abs(point.y - dragStart.y)
        ).integral
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let selection, selection.width >= 4, selection.height >= 4 {
            onFinish?(.region(RegionInfo(display: display, rect: localRect(from: selection))))
        } else if mode == .window, let hovered {
            onFinish?(.window(hovered.0))
        } else {
            selection = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onFinish?(nil)
        case 49: // Space
            mode = mode == .region ? .window : .region
            selection = nil
            updateHover()
            needsDisplay = true
        case 36, 76: // Return / Enter
            if mode == .window, let hovered {
                onFinish?(.window(hovered.0))
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func updateHover() {
        guard mode == .window, let cursor else {
            hovered = nil
            return
        }
        // Smallest window under the cursor is the most likely one the user means.
        hovered = windows
            .filter { $0.1.contains(cursor) }
            .min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }
    }

    /// View coordinates (bottom-left) → display-local points (top-left), the ScreenCaptureKit convention.
    private func localRect(from rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        let highlight = selection ?? (mode == .window ? hovered?.1 : nil)
        if let highlight {
            context.clear(highlight)
            if mode == .window, selection == nil {
                NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
                highlight.fill()
            }
            let border = NSBezierPath(rect: highlight.insetBy(dx: -1, dy: -1))
            border.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            border.stroke()
            drawSizeLabel(for: highlight)
        } else if mode == .region, let cursor {
            drawCrosshair(at: cursor)
        }
        drawHint()
    }

    private func drawCrosshair(at point: NSPoint) {
        NSColor.white.withAlphaComponent(0.7).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: 0, y: point.y + 0.5))
        path.line(to: NSPoint(x: bounds.width, y: point.y + 0.5))
        path.move(to: NSPoint(x: point.x + 0.5, y: 0))
        path.line(to: NSPoint(x: point.x + 0.5, y: bounds.height))
        path.stroke()
    }

    private func drawSizeLabel(for rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        var origin = NSPoint(x: rect.maxX - size.width - 16, y: rect.minY - size.height - 14)
        if origin.y < 4 {
            origin.y = rect.minY + 8
        }
        origin.x = max(origin.x, 4)
        let background = NSRect(x: origin.x - 8, y: origin.y - 4, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawHint() {
        let text = mode == .region
            ? String(localized: "Arraste para selecionar · Espaço escolhe uma janela · Esc cancela")
            : String(localized: "Clique na janela desejada · Espaço volta para área · Esc cancela")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 48)
        let background = NSRect(x: origin.x - 14, y: origin.y - 7, width: size.width + 28, height: size.height + 14)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: background, xRadius: background.height / 2, yRadius: background.height / 2).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
