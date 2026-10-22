// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

#if DEBUG
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Developer tool: `LibreScreen -snapshot <directory>` shows every main screen in a real window,
/// captures it with ScreenCaptureKit (light and dark) and quits. Lets UI changes be reviewed from a
/// terminal that has no Screen Recording permission of its own. Compiled only into Debug builds and
/// only useful once the app itself is authorized to record the screen.
@MainActor
enum DebugSnapshots {
    static func directoryFromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
        guard let index = arguments.firstIndex(of: "-snapshot"), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(container: AppContainer, directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        // Deprecated, but the only way for a freshly launched tool to become active and render key-window chrome.
        NSApp.activate(ignoringOtherApps: true)
        await container.hub.refresh()
        let screens: [(String, AnyView)] = [
            ("hub", AnyView(HubView().environment(container))),
            ("permissions", AnyView(PermissionsView(isOnboarding: true).environment(container))),
            ("settings-general", AnyView(GeneralSettingsTab().environment(container).frame(width: 540))),
            ("settings-video", AnyView(VideoSettingsTab().environment(container).frame(width: 540))),
            ("settings-camera", AnyView(CameraSettingsTab().environment(container).frame(width: 540))),
            ("settings-about", AnyView(AboutTab().environment(container).frame(width: 540)))
        ]
        for (name, view) in screens {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                await capture(view, appearance: appearance, to: directory.appending(path: "\(name)-\(suffix).png"))
            }
        }
        Log.app.info("Snapshots written to \(directory.path, privacy: .private)")
        NSApp.terminate(nil)
    }

    private static func capture(_ view: AnyView, appearance: NSAppearance.Name, to url: URL) async {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Let `.task` modifiers, layout and the glass renderer settle.
        try? await Task.sleep(for: .milliseconds(700))
        defer { window.orderOut(nil) }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                Log.app.error("Snapshot window not found by ScreenCaptureKit")
                return
            }
            let scale = window.backingScaleFactor
            let configuration = SCStreamConfiguration()
            configuration.width = Int(scWindow.frame.width * scale)
            configuration.height = Int(scWindow.frame.height * scale)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try ImageFileWriter().write(image, to: url, format: .png, quality: 1)
        } catch {
            Log.app.error("Snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
