// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

enum ImageFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case png
    case jpeg

    var id: String {
        rawValue
    }

    var fileExtension: String {
        self == .png ? "png" : "jpg"
    }
}

struct ScreenshotSettings: Codable, Sendable, Equatable {
    var format: ImageFormat = .png
    var jpegQuality: Double = 0.9
    var copiesToClipboard = true
    var opensEditor = true
    var showsCursor = false
    var resolution: ResolutionScale = .native
    var playsSound = true
    /// `nil` means the default folder (`~/Pictures/LibreScreen`).
    var outputDirectory: URL?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(ImageFormat.self, forKey: .format) ?? .png
        jpegQuality = try container.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 0.9
        copiesToClipboard = try container.decodeIfPresent(Bool.self, forKey: .copiesToClipboard) ?? true
        opensEditor = try container.decodeIfPresent(Bool.self, forKey: .opensEditor) ?? true
        showsCursor = try container.decodeIfPresent(Bool.self, forKey: .showsCursor) ?? false
        resolution = try container.decodeIfPresent(ResolutionScale.self, forKey: .resolution) ?? .native
        playsSound = try container.decodeIfPresent(Bool.self, forKey: .playsSound) ?? true
        outputDirectory = try container.decodeIfPresent(URL.self, forKey: .outputDirectory)
    }

    func validated() -> ScreenshotSettings {
        var copy = self
        copy.jpegQuality = min(max(copy.jpegQuality, 0.3), 1)
        return copy
    }
}
