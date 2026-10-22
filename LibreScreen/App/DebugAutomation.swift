// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

#if DEBUG
import AppKit
import AVFoundation
import ScreenCaptureKit

/// Developer tool: `LibreScreen -autorecord <seconds>` records the main display without the camera,
/// pausing for two seconds in the middle, then inspects the file and quits. Output goes to the unified
/// log (`log show --predicate 'subsystem == "br.com.asoft.LibreScreen"'`). Debug builds only.
@MainActor
enum DebugAutomation {
    static func wantsScreenshots(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-autoscreenshot")
    }

    /// Captures the main display and a 600×400 region of it, reporting pixel sizes and file paths.
    static func runScreenshots(container: AppContainer) async {
        await container.hub.refresh()
        guard let display = container.hub.selectedDisplay else {
            report("ERROR no display")
            return NSApp.terminate(nil)
        }
        let useCase = TakeScreenshotUseCase(
            permissions: container.permissions,
            screenshots: container.screenshots,
            encoder: container.encoder,
            output: container.output,
            store: container.captures
        )
        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) {
            report("hub display id=\(display.id); SCK displays=\(content.displays.map(\.displayID)) windows=\(content.windows.count)")
        }
        let region = RegionInfo(display: display, rect: CGRect(x: 100, y: 100, width: 600, height: 400))
        for source in [CaptureSource.display(display), .region(region)] {
            do {
                let outcome = try await useCase.execute(source: source, settings: container.settings.settings.screenshot)
                let path = outcome.item.url.path(percentEncoded: false)
                report("screenshot \(source.kind.rawValue): \(outcome.image.width)x\(outcome.image.height) -> \(path)")
            } catch {
                report("ERROR screenshot \(source.kind.rawValue): \(error.localizedDescription)")
            }
        }
        NSApp.terminate(nil)
    }

    static func secondsFromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Int? {
        guard let index = arguments.firstIndex(of: "-autorecord"), arguments.indices.contains(index + 1) else { return nil }
        return Int(arguments[index + 1])
    }

    /// Debug-only reporting straight to stderr so a terminal can read it without the unified log.
    private static func report(_ message: String) {
        Log.app.notice("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("[autorecord] \(message)\n".utf8))
    }

    static func run(container: AppContainer, seconds: Int) async {
        await container.hub.refresh()
        guard let display = container.hub.selectedDisplay else {
            report("ERROR no display")
            return NSApp.terminate(nil)
        }
        var settings = container.settings.settings.recording
        settings.countdownSeconds = 0
        let arguments = ProcessInfo.processInfo.arguments
        var overlay = container.settings.settings.camera
        overlay.enabled = arguments.contains("-with-camera") || arguments.contains("-with-fake-camera")
        if arguments.contains("-no-blur") {
            overlay.blurEnabled = false
        }
        var recorder: any RecordingCoordinating = container.recorder
        var synthetic: SyntheticCameraSource?
        if arguments.contains("-with-fake-camera") {
            let source = SyntheticCameraSource(applyBlur: overlay.blurEnabled)
            source.start()
            synthetic = source
            recorder = RecordingPipeline(cameraSource: source)
            report("synthetic camera started (blur=\(overlay.blurEnabled))")
        } else if overlay.enabled {
            do {
                try await container.camera.start(deviceID: overlay.deviceID, options: CameraProcessingOptions(settings: overlay))
                report("camera started (blur=\(overlay.blurEnabled))")
            } catch {
                report("ERROR camera failed: \(error.localizedDescription)")
                overlay.enabled = false
            }
        }
        await record(
            container: container,
            display: display,
            settings: settings,
            overlay: overlay,
            recorder: recorder,
            synthetic: synthetic,
            seconds: seconds
        )
        NSApp.terminate(nil)
    }

    // swiftlint:disable:next function_parameter_count
    private static func record(
        container: AppContainer,
        display: DisplayInfo,
        settings: RecordingSettings,
        overlay: CameraOverlaySettings,
        recorder: any RecordingCoordinating,
        synthetic: SyntheticCameraSource?,
        seconds: Int
    ) async {
        let useCase = StartRecordingUseCase(permissions: container.permissions, recorder: recorder, output: container.output)
        do {
            // The synthetic camera needs no permission, so the overlay is re-attached after `prepare`.
            var prepareOverlay = overlay
            prepareOverlay.enabled = overlay.enabled && synthetic == nil
            let prepared = try await useCase.prepare(source: .display(display), settings: settings, overlay: prepareOverlay)
            let request = RecordingRequest(
                source: prepared.source,
                settings: prepared.settings,
                overlay: overlay,
                outputURL: prepared.outputURL
            )
            try await useCase.start(request)
            report("started \(request.outputURL.lastPathComponent)")
            let half = max(Double(seconds) / 2, 0.5)
            let monitor = Task { [recorder] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled, let pipeline = recorder as? RecordingPipeline else { return }
                    let statistics = await pipeline.statistics()
                    report("stats: \(statistics.summary)")
                }
            }
            defer { monitor.cancel() }
            try await Task.sleep(for: .seconds(half))
            await recorder.pause()
            let pausedAt = await recorder.elapsedTime()
            report("paused at \(String(format: "%.2f", pausedAt))s")
            try await Task.sleep(for: .seconds(2))
            await recorder.resume()
            try await Task.sleep(for: .seconds(half))
            if let pipeline = recorder as? RecordingPipeline {
                let statistics = await pipeline.statistics()
                report("statistics before stop: \(statistics.summary)")
            }
            let result = try await recorder.stop()
            report("stopped, reported duration \(String(format: "%.2f", result.duration))s")
            synthetic?.stop()
            if overlay.enabled, synthetic == nil {
                await container.camera.stop()
            }
            await inspect(result.url)
        } catch {
            report("ERROR failed: \(error.localizedDescription)")
        }
    }

    private static func inspect(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let size = try await video.first?.load(.naturalSize) ?? .zero
            let frameRate = try await video.first?.load(.nominalFrameRate) ?? 0
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int) ?? 0
            let summary = "duration=\(String(format: "%.2f", duration))s size=\(Int(size.width))x\(Int(size.height))"
                + " fps=\(String(format: "%.1f", frameRate)) audioTracks=\(audio.count) bytes=\(bytes)"
            report("file \(url.path(percentEncoded: false)) \(summary)")
        } catch {
            report("ERROR inspection failed \(error.localizedDescription)")
        }
    }
}
#endif
