// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

#if DEBUG
import AppKit
import ScreenCaptureKit
import SwiftUI
import Synchronization

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
        if let editor = sampleEditor(container: container) {
            await capture(
                AnyView(EditorView(model: editor).frame(width: 1100, height: 720)),
                appearance: .darkAqua,
                to: directory.appending(path: "editor-dark.png")
            )
            if let rendered = editor.renderedImage() {
                try? ImageFileWriter().write(rendered, to: directory.appending(path: "editor-export.png"), format: .png, quality: 1)
            }
        }
        Log.app.info("Snapshots written to \(directory.path, privacy: .private)")
        NSApp.terminate(nil)
    }

    /// An editor over the newest screenshot with one annotation of every kind.
    private static func sampleEditor(container: AppContainer) -> EditorViewModel? {
        let folder = container.output.defaultScreenshotsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast >
                    (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast
            }
        guard
            let url = files?.first,
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let item = CaptureItem(
            kind: .screenshot,
            url: url,
            pixelSize: CGSize(width: image.width, height: image.height),
            sourceSummary: "sample"
        )
        let model = EditorViewModel(item: item, image: image, encoder: ImageFileWriter()) { _ in }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var style = AnnotationStyle()
        style.lineWidth = max(4, width / 400)
        style.fontSize = max(28, width / 60)
        let samples: [AnnotationShape] = [
            .arrow(from: CGPoint(x: width * 0.1, y: height * 0.2), to: CGPoint(x: width * 0.3, y: height * 0.4)),
            .rectangle(CGRect(x: width * 0.4, y: height * 0.15, width: width * 0.25, height: height * 0.2)),
            .ellipse(CGRect(x: width * 0.7, y: height * 0.2, width: width * 0.15, height: height * 0.15)),
            .text("LibreScreen", origin: CGPoint(x: width * 0.1, y: height * 0.6)),
            .number(1, center: CGPoint(x: width * 0.5, y: height * 0.6)),
            .pixelate(CGRect(x: width * 0.6, y: height * 0.55, width: width * 0.2, height: height * 0.15)),
            .highlighter([CGPoint(x: width * 0.1, y: height * 0.8), CGPoint(x: width * 0.45, y: height * 0.8)]),
            .freehand([
                CGPoint(x: width * 0.55, y: height * 0.85),
                CGPoint(x: width * 0.6, y: height * 0.78),
                CGPoint(x: width * 0.66, y: height * 0.88),
                CGPoint(x: width * 0.72, y: height * 0.8)
            ])
        ]
        for (index, shape) in samples.enumerated() {
            var itemStyle = style
            itemStyle.color = RGBAColor.presets[index % RGBAColor.presets.count]
            model.replaceForSnapshot(Annotation(shape: shape, style: itemStyle))
        }
        return model
    }

    /// Runs `operation` on the main actor and gives up after `timeout`, whichever comes first.
    private static func firstResult<T: Sendable>(timeout: Duration, _ operation: @escaping @MainActor () async -> T?) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let resumed = Mutex(false)
            let finish: @Sendable (T?) -> Void = { value in
                let shouldResume = resumed.withLock { already -> Bool in
                    if already {
                        return false
                    }
                    already = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: value)
                }
            }
            Task { @MainActor in await finish(operation()) }
            Task {
                try? await Task.sleep(for: timeout)
                finish(nil)
            }
        }
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
        // Let `.task` modifiers, layout and the glass renderer settle, then size the window to its content:
        // a second instance of the same view can report a near-zero size until its first layout pass.
        try? await Task.sleep(for: .milliseconds(700))
        window.setContentSize(hosting.view.fittingSize)
        try? await Task.sleep(for: .milliseconds(300))
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
            // ScreenCaptureKit stalls while the screen is locked; move on after a few seconds and let the
            // stalled call finish (or not) on its own, which is fine for a debug tool.
            guard let image = await firstResult(timeout: .seconds(8), {
                try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            }) else {
                Log.app.error("Snapshot timed out (screen locked?)")
                return
            }
            try ImageFileWriter().write(image, to: url, format: .png, quality: 1)
        } catch {
            Log.app.error("Snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
