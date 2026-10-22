// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Reads and requests TCC permissions. The only place in the app allowed to trigger a system prompt,
/// and only ever called in response to a user action (pressing Record, enabling the camera, …).
protocol PermissionsChecking: Sendable {
    func status(of permission: Permission) -> PermissionStatus
    func request(_ permission: Permission) async -> PermissionStatus
    @MainActor func openSystemSettings(for permission: Permission)
    /// Relaunches the app, which macOS requires after granting Screen Recording.
    @MainActor func relaunchApplication()
}
