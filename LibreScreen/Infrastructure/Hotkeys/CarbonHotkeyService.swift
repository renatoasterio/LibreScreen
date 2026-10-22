// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import Carbon.HIToolbox

/// Global shortcuts through Carbon's `RegisterEventHotKey`, which works without Accessibility or Input
/// Monitoring permissions. All state lives on the main actor; the Carbon callback hops there. The
/// service lives for the whole app lifetime, so registrations are released by `unregisterAll()` and
/// at process exit rather than in a `deinit`.
@MainActor
final class CarbonHotkeyService: HotkeyRegistering {
    private static let signature: OSType = 0x4C53_4352 // "LSCR"

    private var references: [HotkeyAction: EventHotKeyRef] = [:]
    private var actionsByID: [UInt32: HotkeyAction] = [:]
    private var handler: (@MainActor (HotkeyAction) -> Void)?
    private var eventHandler: EventHandlerRef?

    init() {
        installEventHandler()
    }

    @discardableResult
    func apply(_ settings: HotkeySettings, handler: @escaping @MainActor (HotkeyAction) -> Void) -> [HotkeyAction] {
        unregisterAll()
        self.handler = handler
        var failed: [HotkeyAction] = []
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let hotkey = settings[action], hotkey.isValid else { continue }
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(hotkey.keyCode),
                Self.carbonModifiers(from: hotkey.modifierFlags),
                id,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                references[action] = reference
                actionsByID[id.id] = action
            } else {
                failed.append(action)
                Log.hotkeys.error("Could not register \(action.rawValue, privacy: .public): \(status)")
            }
        }
        return failed
    }

    func unregisterAll() {
        references.values.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        actionsByID.removeAll()
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), Self.carbonCallback, 1, &spec, userData, &eventHandler)
    }

    /// C callback: reads the hotkey id and hands it to the service on the main actor.
    private static let carbonCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        guard status == noErr else { return status }
        let service = Unmanaged<CarbonHotkeyService>.fromOpaque(userData).takeUnretainedValue()
        let id = hotkeyID.id
        Task { @MainActor in service.dispatch(id: id) }
        return noErr
    }

    private func dispatch(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        handler?(action)
    }

    static func carbonModifiers(from flags: UInt) -> UInt32 {
        var result: UInt32 = 0
        if flags & Hotkey.commandFlag != 0 {
            result |= UInt32(cmdKey)
        }
        if flags & Hotkey.shiftFlag != 0 {
            result |= UInt32(shiftKey)
        }
        if flags & Hotkey.optionFlag != 0 {
            result |= UInt32(optionKey)
        }
        if flags & Hotkey.controlFlag != 0 {
            result |= UInt32(controlKey)
        }
        return result
    }
}

/// Converts key codes into the label shown next to the modifier symbols.
enum KeyLabels {
    static func label(keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Escape: "⎋"
        case kVK_Space: "␣"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        default: characters?.uppercased() ?? "?"
        }
    }
}
