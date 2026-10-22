// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A global keyboard shortcut. Modifier flags use the `NSEvent.ModifierFlags` raw value so the
/// Domain stays free of AppKit; Infrastructure converts them to Carbon flags when registering.
struct Hotkey: Codable, Hashable, Sendable {
    static let commandFlag: UInt = 1 << 20
    static let shiftFlag: UInt = 1 << 17
    static let controlFlag: UInt = 1 << 18
    static let optionFlag: UInt = 1 << 19

    let keyCode: UInt16
    let modifierFlags: UInt
    /// Human-readable key, e.g. "R" or "⎋". Computed by Infrastructure at capture time.
    let keyLabel: String

    /// Symbols in the order macOS displays them: ⌃ ⌥ ⇧ ⌘.
    var displayString: String {
        var text = ""
        if modifierFlags & Self.controlFlag != 0 {
            text += "⌃"
        }
        if modifierFlags & Self.optionFlag != 0 {
            text += "⌥"
        }
        if modifierFlags & Self.shiftFlag != 0 {
            text += "⇧"
        }
        if modifierFlags & Self.commandFlag != 0 {
            text += "⌘"
        }
        return text + keyLabel
    }

    /// A shortcut without any modifier would hijack normal typing.
    var isValid: Bool {
        modifierFlags & (Self.commandFlag | Self.controlFlag | Self.optionFlag) != 0
    }
}

enum HotkeyAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case recordDisplay
    case recordWindow
    case recordRegion
    case screenshotDisplay
    case screenshotWindow
    case screenshotRegion
    case stopRecording
    case pauseResumeRecording
    case toggleHub

    var id: String {
        rawValue
    }
}

struct HotkeySettings: Codable, Sendable, Equatable {
    var bindings: [HotkeyAction: Hotkey]

    init(bindings: [HotkeyAction: Hotkey] = HotkeySettings.defaultBindings) {
        self.bindings = bindings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bindings = try container.decodeIfPresent([HotkeyAction: Hotkey].self, forKey: .bindings) ?? Self.defaultBindings
    }

    subscript(action: HotkeyAction) -> Hotkey? {
        get { bindings[action] }
        set { bindings[action] = newValue }
    }

    /// ⌃⌥ avoids collisions with the system's ⇧⌘3/4/5 screenshot shortcuts.
    static let defaultBindings: [HotkeyAction: Hotkey] = {
        let base = Hotkey.controlFlag | Hotkey.optionFlag
        return [
            .recordDisplay: Hotkey(keyCode: 15, modifierFlags: base, keyLabel: "R"),
            .recordWindow: Hotkey(keyCode: 13, modifierFlags: base, keyLabel: "W"),
            .recordRegion: Hotkey(keyCode: 0, modifierFlags: base, keyLabel: "A"),
            .screenshotRegion: Hotkey(keyCode: 1, modifierFlags: base, keyLabel: "S"),
            .screenshotWindow: Hotkey(keyCode: 13, modifierFlags: base | Hotkey.shiftFlag, keyLabel: "W"),
            .screenshotDisplay: Hotkey(keyCode: 1, modifierFlags: base | Hotkey.shiftFlag, keyLabel: "S"),
            .stopRecording: Hotkey(keyCode: 53, modifierFlags: base, keyLabel: "⎋"),
            .pauseResumeRecording: Hotkey(keyCode: 35, modifierFlags: base, keyLabel: "P")
        ]
    }()
}
