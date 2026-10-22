// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

protocol Screenshotting: Sendable {
    func capture(_ request: ScreenshotRequest) async throws -> CGImage
}

/// Encodes still images to disk. Kept behind a protocol so use cases stay testable.
protocol ImageEncoding: Sendable {
    func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double) throws
}
