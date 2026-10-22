// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

/// Owns the AppKit window controllers (hub, floating panels, editors) so that SwiftUI scenes stay
/// limited to the menu bar extra and Settings. Also presents the recording flow's floating UI.
@MainActor
final class WindowCoordinator {
    // lifetime: the container creates and owns this coordinator, so it always outlives it.
    private unowned let container: AppContainer
    private lazy var hub = HubWindowController(container: container)
    private let recordingHUD = RecordingHUDPanelController()
    private let countdown = CountdownPanelController()
    private lazy var thumbnail: CaptureThumbnailPanelController = {
        let controller = CaptureThumbnailPanelController(thumbnails: container.thumbnails, captures: container.captures)
        controller.onRemoved = { [weak self] _ in
            Task { await self?.container.hub.refreshRecents() }
        }
        return controller
    }()

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

extension WindowCoordinator: RecordingPresenting {
    func showCountdown(_ seconds: Int, on display: DisplayInfo?) {
        countdown.show(seconds, on: display) { [weak self] in
            self?.container.recording.cancelCountdown()
        }
    }

    func hideCountdown() {
        countdown.hide()
    }

    func showRecordingHUD(for source: CaptureSource) {
        recordingHUD.show(for: source, recording: container.recording)
    }

    func hideRecordingHUD() {
        recordingHUD.hide()
    }

    func showCaptureResult(_ item: CaptureItem) {
        thumbnail.show(item)
    }

    func recordingDidStart() {
        hideHub()
    }
}
