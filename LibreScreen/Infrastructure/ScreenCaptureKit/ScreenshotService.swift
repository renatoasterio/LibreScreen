// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import ScreenCaptureKit

/// Still captures through `SCScreenshotManager`, at native or 1× resolution. Regions are captured as
/// the whole display and cropped: `sourceRect` on a one-shot capture proved unreliable (it can hang).
struct ScreenshotService: Screenshotting {
    func capture(_ request: ScreenshotRequest) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = try ContentFilterFactory.filter(for: request.source, content: content)
        let captureSource: CaptureSource = if case let .region(region) = request.source {
            .display(region.display)
        } else {
            request.source
        }
        let pixelSize = captureSource.pixelSize(for: request.resolution)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = request.showsCursor
        configuration.captureResolution = .best
        configuration.scalesToFit = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw LibreScreenError.captureFailed(reason: error.localizedDescription)
        }
        guard case let .region(region) = request.source else { return image }
        return try Self.crop(image, to: region, resolution: request.resolution)
    }

    /// Crops a display capture to a region given in display-local points.
    static func crop(_ image: CGImage, to region: RegionInfo, resolution: ResolutionScale) throws -> CGImage {
        let factor = resolution == .native ? region.display.scaleFactor : 1
        let rect = CGRect(
            x: region.rect.minX * factor,
            y: region.rect.minY * factor,
            width: region.rect.width * factor,
            height: region.rect.height * factor
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else {
            throw LibreScreenError.captureFailed(reason: "crop")
        }
        return cropped
    }
}
