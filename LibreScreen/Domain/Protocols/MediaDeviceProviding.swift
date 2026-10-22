// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Enumerates cameras and microphones. Listing never triggers a permission prompt.
protocol MediaDeviceProviding: Sendable {
    func cameras() -> [MediaDevice]
    func microphones() -> [MediaDevice]
}
