// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        container.recording.presenter = container.windows
        container.hub.regionSelector = container.windows
        container.screenshot.presentResult = { [container] item in container.windows.showCaptureResult(item) }
        container.screenshot.openEditor = { [container] item, image in container.windows.openEditor(for: item, image: image) }
        container.hub.editorOpener = container.windows
        #if DEBUG
        if let directory = DebugSnapshots.directoryFromArguments() {
            Task { await DebugSnapshots.run(container: container, directory: directory) }
            return
        }
        if DebugAutomation.wantsScreenshots() {
            Task { await DebugAutomation.runScreenshots(container: container) }
            return
        }
        if let seconds = DebugAutomation.secondsFromArguments() {
            Task { await DebugAutomation.run(container: container, seconds: seconds) }
            return
        }
        #endif
        container.windows.applyActivationPolicy(showsInDock: container.settings.settings.general.showsInDock)
        container.windows.showHub()
        container.cameraCoordinator.activate()
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard container.recording.isRecordingOrPaused else { return .terminateNow }
        // Finish the file before quitting so nothing recorded is lost.
        Task { @MainActor in
            await container.recording.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
