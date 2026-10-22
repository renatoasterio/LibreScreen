// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A camera or microphone as presented in device menus.
struct MediaDevice: Identifiable, Hashable, Sendable, Codable {
    enum Kind: String, Codable, Sendable {
        case camera
        case microphone
    }

    let id: String
    let name: String
    let kind: Kind
    /// Built-in devices are listed first and used as the default choice.
    let isBuiltIn: Bool
}
