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
        container.hotkeys.activate { [container] action in
            Task { await Self.perform(action, in: container) }
        }
        Log.app.info("LibreScreen launched")
    }

    private static func perform(_ action: HotkeyAction, in container: AppContainer) async {
        switch action {
        case .recordDisplay: await container.hub.quickAction(mode: .record, kind: .display)
        case .recordWindow: await container.hub.quickAction(mode: .record, kind: .window)
        case .recordRegion: await container.hub.quickAction(mode: .record, kind: .region)
        case .screenshotDisplay: await container.hub.quickAction(mode: .screenshot, kind: .display)
        case .screenshotWindow: await container.hub.quickAction(mode: .screenshot, kind: .window)
        case .screenshotRegion: await container.hub.quickAction(mode: .screenshot, kind: .region)
        case .stopRecording: await container.recording.stop()
        case .pauseResumeRecording: await container.recording.togglePause()
        case .toggleHub: container.windows.toggleHub()
        }
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
