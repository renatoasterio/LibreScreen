// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

/// Owns the AppKit window controllers (hub, floating panels, editors) so that SwiftUI scenes stay
/// limited to the menu bar extra and Settings.
@MainActor
final class WindowCoordinator {
    // lifetime: the container creates and owns this coordinator, so it always outlives it.
    private unowned let container: AppContainer
    private lazy var hub = HubWindowController(container: container)

    init(container: AppContainer) {
        self.container = container
    }

    var isHubVisible: Bool {
        hub.window?.isVisible ?? false
    }

    func showHub() {
        hub.show()
    }

    func hideHub() {
        hub.close()
    }

    func toggleHub() {
        if isHubVisible, hub.window?.isKeyWindow == true {
            hideHub()
        } else {
            showHub()
        }
    }

    /// Applies the Dock visibility preference. Accessory apps keep their windows but lose the Dock tile.
    func applyActivationPolicy(showsInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = showsInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
