// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// The capture history shown in Recents.
protocol CaptureStoring: Sendable {
    func items() async -> [CaptureItem]
    func add(_ item: CaptureItem) async
    func remove(_ id: CaptureItem.ID, deletingFile: Bool) async throws
}
