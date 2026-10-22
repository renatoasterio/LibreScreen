// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// The main window: a compact, title-less panel hosting `HubView`.
@MainActor
final class HubWindowController: NSWindowController {
    init(container: AppContainer) {
        let hosting = NSHostingController(rootView: HubView().environment(container))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "LibreScreen"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("HubWindow")
        window.identifier = NSUserInterfaceItemIdentifier("hub")
        window.collectionBehavior = [.moveToActiveSpace]
        // Never let the hub itself appear in a recording or screenshot.
        window.sharingType = .none
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
