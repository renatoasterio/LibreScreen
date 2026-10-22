// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// Captures, encodes, stores and records a screenshot in the history.
struct TakeScreenshotUseCase: Sendable {
    struct Outcome: Sendable {
        let item: CaptureItem
        let image: CGImage
    }

    let permissions: any PermissionsChecking
    let screenshots: any Screenshotting
    let encoder: any ImageEncoding
    let output: any OutputLocating
    let store: any CaptureStoring

    func execute(source: CaptureSource, settings: ScreenshotSettings, date: Date = Date()) async throws -> Outcome {
        var status = permissions.status(of: .screenRecording)
        if status == .notDetermined {
            status = await permissions.request(.screenRecording)
        }
        guard status.isAuthorized else {
            throw LibreScreenError.permissionDenied(.screenRecording)
        }

        let request = ScreenshotRequest(source: source, showsCursor: settings.showsCursor, resolution: settings.resolution)
        let image = try await screenshots.capture(request)
        let url = try output.screenshotURL(
            format: settings.format,
            source: source,
            directory: settings.outputDirectory,
            date: date
        )
        try encoder.write(image, to: url, format: settings.format, quality: settings.jpegQuality)

        let item = CaptureItem(
            kind: .screenshot,
            url: url,
            createdAt: date,
            pixelSize: CGSize(width: image.width, height: image.height),
            sourceSummary: source.summary
        )
        await store.add(item)
        return Outcome(item: item, image: image)
    }
}
