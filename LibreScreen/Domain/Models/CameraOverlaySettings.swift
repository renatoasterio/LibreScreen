// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

enum OverlayShape: String, Codable, CaseIterable, Sendable, Identifiable {
    case circle
    case roundedRectangle

    var id: String {
        rawValue
    }
}

enum OverlaySize: String, Codable, CaseIterable, Sendable, Identifiable {
    case small
    case medium
    case large

    var id: String {
        rawValue
    }

    /// Bubble height as a fraction of the captured frame height.
    var fractionOfHeight: CGFloat {
        switch self {
        case .small: 0.18
        case .medium: 0.26
        case .large: 0.36
        }
    }
}

enum OverlayCorner: String, Codable, CaseIterable, Sendable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String {
        rawValue
    }
}

/// What replaces the room behind the person.
enum CameraBackgroundMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case blur
    case image

    var id: String {
        rawValue
    }
}

/// How the webcam bubble looks and where it sits. Shared by the live preview and the compositor,
/// so what the user sees on screen is exactly what lands in the file.
struct CameraOverlaySettings: Codable, Sendable, Equatable {
    static let aspectRatio: CGFloat = 1.0
    static let marginFraction: CGFloat = 0.025

    var enabled = false
    var deviceID: String?
    var shape: OverlayShape = .circle
    var size: OverlaySize = .medium
    var corner: OverlayCorner = .bottomRight
    var mirrored = true
    var background: CameraBackgroundMode = .blur
    /// Library file used when `background` is `.image`.
    var backgroundImageURL: URL?
    /// 0 (subtle) … 1 (strong).
    var blurIntensity: Double = 0.6
    var showsBorder = true
    var showsShadow = true

    private enum CodingKeys: String, CodingKey {
        case enabled, deviceID, shape, size, corner, mirrored, background, backgroundImageURL
        case blurIntensity, showsBorder, showsShadow
        /// Pre-1.0 settings stored a boolean instead of `background`.
        case blurEnabled
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        shape = try container.decodeIfPresent(OverlayShape.self, forKey: .shape) ?? .circle
        size = try container.decodeIfPresent(OverlaySize.self, forKey: .size) ?? .medium
        corner = try container.decodeIfPresent(OverlayCorner.self, forKey: .corner) ?? .bottomRight
        mirrored = try container.decodeIfPresent(Bool.self, forKey: .mirrored) ?? true
        if let mode = try container.decodeIfPresent(CameraBackgroundMode.self, forKey: .background) {
            background = mode
        } else {
            background = try container.decodeIfPresent(Bool.self, forKey: .blurEnabled) ?? true ? .blur : .none
        }
        backgroundImageURL = try container.decodeIfPresent(URL.self, forKey: .backgroundImageURL)
        blurIntensity = try container.decodeIfPresent(Double.self, forKey: .blurIntensity) ?? 0.6
        showsBorder = try container.decodeIfPresent(Bool.self, forKey: .showsBorder) ?? true
        showsShadow = try container.decodeIfPresent(Bool.self, forKey: .showsShadow) ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(deviceID, forKey: .deviceID)
        try container.encode(shape, forKey: .shape)
        try container.encode(size, forKey: .size)
        try container.encode(corner, forKey: .corner)
        try container.encode(mirrored, forKey: .mirrored)
        try container.encode(background, forKey: .background)
        try container.encodeIfPresent(backgroundImageURL, forKey: .backgroundImageURL)
        try container.encode(blurIntensity, forKey: .blurIntensity)
        try container.encode(showsBorder, forKey: .showsBorder)
        try container.encode(showsShadow, forKey: .showsShadow)
    }

    func validated() -> CameraOverlaySettings {
        var copy = self
        copy.blurIntensity = min(max(copy.blurIntensity, 0), 1)
        return copy
    }

    /// The bubble's rectangle inside a frame of `frameSize` (same unit as the frame, top-left origin).
    func overlayRect(in frameSize: CGSize) -> CGRect {
        let side = (frameSize.height * size.fractionOfHeight).rounded(.down)
        let margin = (frameSize.height * Self.marginFraction).rounded(.down)
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            x = margin
            y = margin
        case .topRight:
            x = frameSize.width - side - margin
            y = margin
        case .bottomLeft:
            x = margin
            y = frameSize.height - side - margin
        case .bottomRight:
            x = frameSize.width - side - margin
            y = frameSize.height - side - margin
        }
        return CGRect(x: max(x, 0), y: max(y, 0), width: side, height: side)
    }

    /// Corner radius for `roundedRectangle`, proportional to the bubble size.
    func cornerRadius(forSide side: CGFloat) -> CGFloat {
        switch shape {
        case .circle: side / 2
        case .roundedRectangle: side * 0.18
        }
    }
}
