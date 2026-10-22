// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AVFoundation
import CoreGraphics
import ImageIO

/// Small cached previews for recordings (first frame) and screenshots (ImageIO thumbnail).
actor ThumbnailLoader {
    static let maximumEntries = 64

    private var cache: [URL: CGImage] = [:]
    private var order: [URL] = []

    func thumbnail(for item: CaptureItem, maxPixelSize: CGFloat = 480) async -> CGImage? {
        if let cached = cache[item.url] {
            return cached
        }
        let image: CGImage? = switch item.kind {
        case .recording: await Self.videoFrame(url: item.url, maxPixelSize: maxPixelSize)
        case .screenshot: Self.imageThumbnail(url: item.url, maxPixelSize: maxPixelSize)
        }
        if let image {
            store(image, for: item.url)
        }
        return image
    }

    func invalidate(_ url: URL) {
        cache[url] = nil
        order.removeAll { $0 == url }
    }

    private func store(_ image: CGImage, for url: URL) {
        cache[url] = image
        order.append(url)
        while order.count > Self.maximumEntries, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
    }

    private static func videoFrame(url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let duration = await (try? asset.load(.duration).seconds) ?? 0
        let time = CMTime(seconds: min(0.5, duration / 2), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    private static func imageThumbnail(url: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
