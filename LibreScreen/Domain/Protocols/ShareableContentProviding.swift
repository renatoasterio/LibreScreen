// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// Lists what can be captured. Displays never need a permission; windows and thumbnails do.
protocol ShareableContentProviding: Sendable {
    func displays() async throws -> [DisplayInfo]
    /// Empty when Screen Recording is not authorized.
    func windows() async throws -> [WindowInfo]
    func thumbnail(for source: CaptureSource, maxPixelSize: CGFloat) async throws -> CGImage
}
