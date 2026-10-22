// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// A recording or screenshot the app produced, shown in the Recents strip.
struct CaptureItem: Identifiable, Hashable, Sendable, Codable {
    enum Kind: String, Codable, Sendable {
        case recording
        case screenshot
    }

    let id: UUID
    let kind: Kind
    let url: URL
    let createdAt: Date
    /// Seconds, recordings only.
    let duration: TimeInterval?
    let pixelSize: CGSize
    /// What was captured, e.g. the display name or window title.
    let sourceSummary: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        url: URL,
        createdAt: Date = Date(),
        duration: TimeInterval? = nil,
        pixelSize: CGSize,
        sourceSummary: String
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.createdAt = createdAt
        self.duration = duration
        self.pixelSize = pixelSize
        self.sourceSummary = sourceSummary
    }
}
