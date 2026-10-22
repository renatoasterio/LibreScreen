// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// Everything the pipeline needs to produce one recording.
struct RecordingRequest: Sendable, Equatable {
    let source: CaptureSource
    let settings: RecordingSettings
    let overlay: CameraOverlaySettings
    let outputURL: URL
}

struct RecordingResult: Sendable, Equatable {
    let url: URL
    let duration: TimeInterval
    let pixelSize: CGSize
    let startedAt: Date
}

/// Progress reported by the pipeline while a recording is active.
enum RecordingEvent: Sendable, Equatable {
    case started
    case paused
    case resumed
    case microphoneLevel(Float)
    case failed(LibreScreenError)
}

/// The user-visible state machine owned by `RecordingViewModel`.
enum RecordingPhase: Sendable, Equatable {
    case idle
    case preparing
    case countdown(Int)
    case recording
    case paused
    case finishing

    var isActive: Bool {
        self != .idle
    }

    var canStop: Bool {
        self == .recording || self == .paused
    }
}

struct ScreenshotRequest: Sendable, Equatable {
    let source: CaptureSource
    let showsCursor: Bool
    let resolution: ResolutionScale
}
