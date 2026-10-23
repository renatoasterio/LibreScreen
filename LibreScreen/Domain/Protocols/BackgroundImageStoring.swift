// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// The user's library of virtual-background images for the webcam bubble.
protocol BackgroundImageStoring: Sendable {
    /// Images currently in the library, newest first.
    func images() -> [URL]
    /// Copies the given files into the library and returns the stored copies. Non-images are skipped.
    func importImages(from urls: [URL]) throws -> [URL]
    func remove(_ url: URL) throws
}
