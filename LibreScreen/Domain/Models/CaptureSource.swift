// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// How the output resolution relates to the source's size in points.
enum ResolutionScale: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Points × backing scale factor (full Retina resolution).
    case native
    /// 1× (smaller files, same framing).
    case points

    var id: String {
        rawValue
    }
}

/// A physical display. Frames use the ScreenCaptureKit convention: global points, top-left origin.
struct DisplayInfo: Identifiable, Hashable, Sendable, Codable {
    let id: UInt32
    let name: String
    let frame: CGRect
    let scaleFactor: CGFloat
    let isMain: Bool

    var pointSize: CGSize {
        frame.size
    }
}

/// An on-screen window owned by another application.
struct WindowInfo: Identifiable, Hashable, Sendable, Codable {
    let id: UInt32
    let title: String
    let applicationName: String
    let bundleIdentifier: String?
    let processID: Int32
    /// Global points, top-left origin.
    let frame: CGRect
    /// Backing scale factor of the display that contains most of the window.
    let scaleFactor: CGFloat
    let isOnScreen: Bool

    var displayTitle: String {
        title.isEmpty ? applicationName : title
    }
}

/// A rectangular region of one display, in that display's local points (top-left origin).
struct RegionInfo: Hashable, Sendable, Codable {
    let display: DisplayInfo
    let rect: CGRect

    /// The region expressed in global points (top-left origin).
    var globalRect: CGRect {
        rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
    }
}

/// The three ways a user can pick what to capture.
enum SourceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case display
    case window
    case region

    var id: String {
        rawValue
    }
}

/// What gets captured. Shared by recordings and screenshots.
enum CaptureSource: Hashable, Sendable, Codable {
    case display(DisplayInfo)
    case window(WindowInfo)
    case region(RegionInfo)

    var kind: SourceKind {
        switch self {
        case .display: .display
        case .window: .window
        case .region: .region
        }
    }

    /// The display that owns the source, when it is known without querying the system.
    var displayInfo: DisplayInfo? {
        switch self {
        case let .display(display): display
        case let .region(region): region.display
        case .window: nil
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case let .display(display): display.scaleFactor
        case let .window(window): window.scaleFactor
        case let .region(region): region.display.scaleFactor
        }
    }

    var pointSize: CGSize {
        switch self {
        case let .display(display): display.frame.size
        case let .window(window): window.frame.size
        case let .region(region): region.rect.size
        }
    }

    /// Output size in pixels, rounded down to even values because hardware encoders require it.
    func pixelSize(for resolution: ResolutionScale) -> CGSize {
        let factor = resolution == .native ? scaleFactor : 1
        let width = floor(pointSize.width * factor / 2) * 2
        let height = floor(pointSize.height * factor / 2) * 2
        return CGSize(width: max(width, 2), height: max(height, 2))
    }

    /// Short human-readable description used in file names and the capture history.
    var summary: String {
        switch self {
        case let .display(display): display.name
        case let .window(window): window.displayTitle
        case let .region(region): "\(Int(region.rect.width))×\(Int(region.rect.height))"
        }
    }
}
