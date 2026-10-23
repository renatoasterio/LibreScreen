// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LibreScreen

struct AppSettingsTests {
    @Test func roundTripsThroughJSON() throws {
        var settings = AppSettings()
        settings.recording.codec = .hevc
        settings.camera.corner = .topLeft
        settings.hotkeys[.toggleHub] = Hotkey(keyCode: 4, modifierFlags: Hotkey.commandFlag | Hotkey.shiftFlag, keyLabel: "H")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let json = #"{"recording":{"codec":"hevc"}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.recording.codec == .hevc)
        #expect(decoded.recording.frameRate == .fps30)
        #expect(decoded.camera.shape == .circle)
        #expect(decoded.general.showsInDock)
    }

    @Test func legacyBlurFlagMigratesToBackgroundMode() throws {
        let legacyOff = #"{"camera":{"blurEnabled":false}}"#
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(legacyOff.utf8)).camera.background == .none)
        let legacyOn = #"{"camera":{"blurEnabled":true}}"#
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(legacyOn.utf8)).camera.background == .blur)
        let modern = #"{"camera":{"background":"image","backgroundImageURL":"file:///tmp/bg.png"}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(modern.utf8))
        #expect(decoded.camera.background == .image)
        #expect(decoded.camera.backgroundImageURL?.lastPathComponent == "bg.png")
    }

    @Test func validationDropsInvalidHotkeysAndCountdowns() {
        var settings = AppSettings()
        settings.recording.countdownSeconds = 42
        settings.hotkeys[.recordDisplay] = Hotkey(keyCode: 15, modifierFlags: 0, keyLabel: "R")
        let validated = settings.validated()
        #expect(validated.recording.countdownSeconds == 3)
        #expect(validated.hotkeys[.recordDisplay] == nil)
    }

    @Test func bitrateScalesWithPixelsAndStaysInRange() {
        var settings = RecordingSettings()
        settings.quality = .high
        let small = settings.bitrate(for: CGSize(width: 640, height: 480))
        let large = settings.bitrate(for: CGSize(width: 3840, height: 2160))
        #expect(small >= RecordingSettings.minimumBitrate)
        #expect(large <= RecordingSettings.maximumBitrate)
        #expect(large > small)
    }

    @Test func hotkeyDisplayStringUsesMacOrder() {
        let hotkey = Hotkey(keyCode: 15, modifierFlags: Hotkey.commandFlag | Hotkey.controlFlag | Hotkey.shiftFlag, keyLabel: "R")
        #expect(hotkey.displayString == "⌃⇧⌘R")
    }
}
