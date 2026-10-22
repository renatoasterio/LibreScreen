// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Drives one recording at a time. Implemented by the real-time pipeline in Infrastructure.
protocol RecordingCoordinating: AnyObject, Sendable {
    func start(_ request: RecordingRequest) async throws
    func pause() async
    func resume() async
    func stop() async throws -> RecordingResult
    /// Stops and discards the partial file.
    func cancel() async
    /// Seconds recorded so far, excluding paused time.
    func elapsedTime() async -> TimeInterval
    func events() -> AsyncStream<RecordingEvent>
}
