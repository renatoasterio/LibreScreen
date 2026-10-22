// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

@MainActor
@Observable
final class PermissionsViewModel {
    private(set) var statuses: [Permission: PermissionStatus] = [:]
    /// Screen Recording only takes effect after the app is relaunched.
    private(set) var suggestsRelaunch = false

    private let permissions: any PermissionsChecking

    init(permissions: any PermissionsChecking) {
        self.permissions = permissions
    }

    func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? permissions.status(of: permission)
    }

    var allAuthorized: Bool {
        Permission.allCases.allSatisfy { status(of: $0).isAuthorized }
    }

    func refresh() {
        for permission in Permission.allCases {
            statuses[permission] = permissions.status(of: permission)
        }
        if status(of: .screenRecording).isAuthorized {
            suggestsRelaunch = false
        }
    }

    func request(_ permission: Permission) async {
        let result = await permissions.request(permission)
        statuses[permission] = result
        if permission == .screenRecording, !result.isAuthorized {
            suggestsRelaunch = true
        }
    }

    func openSystemSettings(for permission: Permission) {
        permissions.openSystemSettings(for: permission)
        if permission == .screenRecording {
            suggestsRelaunch = true
        }
    }

    func relaunch() {
        permissions.relaunchApplication()
    }
}
