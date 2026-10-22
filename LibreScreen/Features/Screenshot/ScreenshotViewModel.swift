// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import Foundation
import Observation

/// Runs the screenshot use case and the post-capture behaviour (clipboard, sound, thumbnail, editor).
@MainActor
@Observable
final class ScreenshotViewModel {
    private(set) var isCapturing = false

    var errorHandler: (@MainActor (any Error) -> Void)?
    var didStoreItem: (@MainActor (CaptureItem) -> Void)?
    /// Shows the floating thumbnail; set by the composition root.
    var presentResult: (@MainActor (CaptureItem) -> Void)?
    /// Opens the annotation editor; set once the editor exists.
    var openEditor: (@MainActor (CaptureItem, CGImage) -> Void)?

    private let useCase: TakeScreenshotUseCase
    private let settings: SettingsStore

    init(useCase: TakeScreenshotUseCase, settings: SettingsStore) {
        self.useCase = useCase
        self.settings = settings
    }

    func capture(source: CaptureSource) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        let screenshotSettings = settings.settings.screenshot
        do {
            let outcome = try await useCase.execute(source: source, settings: screenshotSettings)
            if screenshotSettings.copiesToClipboard {
                CaptureItemActions.copy(outcome.item)
            }
            if screenshotSettings.playsSound, settings.settings.general.playsSounds {
                Self.playShutterSound()
            }
            didStoreItem?(outcome.item)
            if screenshotSettings.opensEditor, let openEditor {
                openEditor(outcome.item, outcome.image)
            } else if settings.settings.general.showsThumbnailPanel {
                presentResult?(outcome.item)
            }
        } catch {
            Log.capture.error("Screenshot failed: \(error.localizedDescription, privacy: .public)")
            errorHandler?(error)
        }
    }

    private static func playShutterSound() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aiff"
        guard FileManager.default.fileExists(atPath: path), let sound = NSSound(contentsOfFile: path, byReference: true) else {
            NSSound.beep()
            return
        }
        sound.play()
    }
}
