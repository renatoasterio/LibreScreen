// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Root of everything the user can configure. Stored as JSON by `SettingsStore`.
struct AppSettings: Codable, Sendable, Equatable {
    var recording = RecordingSettings()
    var camera = CameraOverlaySettings()
    var screenshot = ScreenshotSettings()
    var general = GeneralSettings()
    var hotkeys = HotkeySettings()

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recording = try container.decodeIfPresent(RecordingSettings.self, forKey: .recording) ?? RecordingSettings()
        camera = try container.decodeIfPresent(CameraOverlaySettings.self, forKey: .camera) ?? CameraOverlaySettings()
        screenshot = try container.decodeIfPresent(ScreenshotSettings.self, forKey: .screenshot) ?? ScreenshotSettings()
        general = try container.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? GeneralSettings()
        hotkeys = try container.decodeIfPresent(HotkeySettings.self, forKey: .hotkeys) ?? HotkeySettings()
    }

    /// Clamps every value loaded from disk into its supported range.
    func validated() -> AppSettings {
        var copy = self
        copy.recording = recording.validated()
        copy.camera = camera.validated()
        copy.screenshot = screenshot.validated()
        copy.hotkeys.bindings = hotkeys.bindings.filter { $0.value.isValid }
        return copy
    }
}
