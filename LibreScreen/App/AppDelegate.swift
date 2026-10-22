// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let directory = DebugSnapshots.directoryFromArguments() {
            Task { await DebugSnapshots.run(container: container, directory: directory) }
            return
        }
        #endif
        container.windows.applyActivationPolicy(showsInDock: container.settings.settings.general.showsInDock)
        container.windows.showHub()
        Log.app.info("LibreScreen launched")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        container.windows.showHub()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The menu bar extra keeps the app useful without any window.
        false
    }
}
