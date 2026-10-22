// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Carbon.HIToolbox
import Testing
@testable import LibreScreen

struct HotkeyTests {
    @Test @MainActor func carbonModifiersMapEveryFlag() {
        let flags = Hotkey.commandFlag | Hotkey.shiftFlag | Hotkey.optionFlag | Hotkey.controlFlag
        let carbon = CarbonHotkeyService.carbonModifiers(from: flags)
        #expect(carbon & UInt32(cmdKey) != 0)
        #expect(carbon & UInt32(shiftKey) != 0)
        #expect(carbon & UInt32(optionKey) != 0)
        #expect(carbon & UInt32(controlKey) != 0)
        #expect(CarbonHotkeyService.carbonModifiers(from: 0) == 0)
    }

    @Test func keyLabelsCoverSpecialKeys() {
        #expect(KeyLabels.label(keyCode: UInt16(kVK_Escape), characters: nil) == "⎋")
        #expect(KeyLabels.label(keyCode: UInt16(kVK_F5), characters: nil) == "F5")
        #expect(KeyLabels.label(keyCode: UInt16(kVK_ANSI_R), characters: "r") == "R")
    }

    @Test func defaultBindingsAreValidAndUnique() {
        let bindings = HotkeySettings.defaultBindings
        #expect(bindings.values.allSatisfy(\.isValid))
        let combos = bindings.values.map { "\($0.keyCode)-\($0.modifierFlags)" }
        #expect(Set(combos).count == combos.count)
    }

    @Test func hotkeyWithoutModifiersIsInvalid() {
        #expect(!Hotkey(keyCode: 15, modifierFlags: Hotkey.shiftFlag, keyLabel: "R").isValid)
        #expect(Hotkey(keyCode: 15, modifierFlags: Hotkey.controlFlag, keyLabel: "R").isValid)
    }
}
