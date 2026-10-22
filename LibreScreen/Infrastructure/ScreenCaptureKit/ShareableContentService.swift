// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import ScreenCaptureKit

/// Displays come from AppKit/CoreGraphics (no permission needed); windows and thumbnails come from
/// ScreenCaptureKit and are only queried once Screen Recording is authorized.
final class ShareableContentService: ShareableContentProviding {
    static let minimumWindowSide: CGFloat = 48

    private let permissions: any PermissionsChecking

    init(permissions: any PermissionsChecking) {
        self.permissions = permissions
    }

    func displays() async throws -> [DisplayInfo] {
        let displays = await MainActor.run { DisplayCatalog.displays() }
        guard !displays.isEmpty else { throw LibreScreenError.noDisplaysAvailable }
        return displays
    }

    func windows() async throws -> [WindowInfo] {
        guard permissions.status(of: .screenRecording).isAuthorized else { return [] }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let displays = try await displays()
        let ownBundleID = Bundle.main.bundleIdentifier
        return content.windows.compactMap { window -> WindowInfo? in
            guard
                let app = window.owningApplication,
                app.bundleIdentifier != ownBundleID,
                window.windowLayer == 0,
                window.frame.width >= Self.minimumWindowSide,
                window.frame.height >= Self.minimumWindowSide else { return nil }
            let scale = CaptureCoordinates.display(containing: window.frame, in: displays)?.scaleFactor ?? 2
            return WindowInfo(
                id: window.windowID,
                title: window.title ?? "",
                applicationName: app.applicationName,
                bundleIdentifier: app.bundleIdentifier,
                processID: app.processID,
                frame: window.frame,
                scaleFactor: scale,
                isOnScreen: window.isOnScreen
            )
        }
        .sorted { lhs, rhs in
            if lhs.applicationName != rhs.applicationName {
                return lhs.applicationName.localizedStandardCompare(rhs.applicationName) == .orderedAscending
            }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    func thumbnail(for source: CaptureSource, maxPixelSize: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = try ContentFilterFactory.filter(for: source, content: content)
        let configuration = SCStreamConfiguration()
        // Regions are captured as their display at reduced size, then cropped.
        let size = source.displayInfo.map(\.pointSize) ?? source.pointSize
        let ratio = min(maxPixelSize / max(size.width, 1), maxPixelSize / max(size.height, 1), 1)
        configuration.width = max(Int(size.width * ratio), 2)
        configuration.height = max(Int(size.height * ratio), 2)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard case let .region(region) = source else { return image }
        let scaled = RegionInfo(display: region.display, rect: CGRect(
            x: region.rect.minX * ratio,
            y: region.rect.minY * ratio,
            width: region.rect.width * ratio,
            height: region.rect.height * ratio
        ))
        return try ScreenshotService.crop(image, to: scaled, resolution: .points)
    }
}

/// Display enumeration without ScreenCaptureKit. Frames are converted to the top-left-origin global space.
@MainActor
enum DisplayCatalog {
    static func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                frame: CGDisplayBounds(id),
                scaleFactor: screen.backingScaleFactor,
                isMain: CGDisplayIsMain(id) != 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain {
                return lhs.isMain
            }
            return lhs.frame.minX < rhs.frame.minX
        }
    }
}
