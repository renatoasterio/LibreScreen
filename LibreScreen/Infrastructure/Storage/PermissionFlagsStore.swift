// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Remembers which permissions were already requested. CoreGraphics cannot tell "never asked" from
/// "denied" for Screen Recording, so the app keeps its own flag.
/// `UserDefaults` is documented as thread-safe, which is what the unchecked conformance relies on.
final class PermissionFlagsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func hasRequested(_ permission: Permission) -> Bool {
        defaults.bool(forKey: key(for: permission))
    }

    func markRequested(_ permission: Permission) {
        defaults.set(true, forKey: key(for: permission))
    }

    private func key(for permission: Permission) -> String {
        "permissions.requested.\(permission.rawValue)"
    }
}
