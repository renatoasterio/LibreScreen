// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Resolves where new files go and gives them unique, sanitised names.
protocol OutputLocating: Sendable {
    var defaultRecordingsDirectory: URL { get }
    var defaultScreenshotsDirectory: URL { get }
    func recordingURL(container: VideoContainer, source: CaptureSource, directory: URL?, date: Date) throws -> URL
    func screenshotURL(format: ImageFormat, source: CaptureSource, directory: URL?, date: Date) throws -> URL
}
