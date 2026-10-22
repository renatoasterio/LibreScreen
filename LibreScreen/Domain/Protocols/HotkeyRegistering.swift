// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

@MainActor
protocol HotkeyRegistering: AnyObject {
    /// Replaces every registered shortcut with `settings`. Actions whose shortcut cannot be registered are reported.
    @discardableResult
    func apply(_ settings: HotkeySettings, handler: @escaping @MainActor (HotkeyAction) -> Void) -> [HotkeyAction]
    func unregisterAll()
}
