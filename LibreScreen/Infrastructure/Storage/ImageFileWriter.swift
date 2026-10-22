// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes PNG/JPEG with ImageIO. Writes to a temporary file first, then moves it into place atomically.
struct ImageFileWriter: ImageEncoding {
    /// FileManager is not Sendable; the shared instance is thread-safe for these calls.
    private var fileManager: FileManager {
        .default
    }

    func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double) throws {
        let type: UTType = format == .png ? .png : .jpeg
        let temporary = fileManager.temporaryDirectory.appending(path: "\(UUID().uuidString).\(format.fileExtension)")
        defer { try? fileManager.removeItem(at: temporary) }

        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type.identifier as CFString, 1, nil) else {
            throw LibreScreenError.exportFailed(reason: "CGImageDestination")
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LibreScreenError.exportFailed(reason: "CGImageDestinationFinalize")
        }

        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }
}
