// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A privacy permission governed by macOS TCC (Transparency, Consent and Control).
enum Permission: String, CaseIterable, Codable, Sendable, Identifiable {
    case screenRecording
    case camera
    case microphone

    var id: String {
        rawValue
    }
}

/// The user's decision for a permission, normalised across CoreGraphics and AVFoundation.
enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized

    var isAuthorized: Bool {
        self == .authorized
    }

    /// True when asking again cannot help and the user must go to System Settings.
    var requiresSystemSettings: Bool {
        self == .denied || self == .restricted
    }
}
