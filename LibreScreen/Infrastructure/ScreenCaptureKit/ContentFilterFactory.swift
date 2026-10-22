// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import ScreenCaptureKit

/// Builds `SCContentFilter`s from a `CaptureSource`, always excluding LibreScreen's own windows.
enum ContentFilterFactory {
    static func filter(for source: CaptureSource, content: SCShareableContent) throws -> SCContentFilter {
        let ownApplications = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        switch source {
        case .display, .region:
            guard
                let display = source.displayInfo,
                let scDisplay = content.displays.first(where: { $0.displayID == display.id }) else {
                throw LibreScreenError.sourceUnavailable
            }
            return SCContentFilter(display: scDisplay, excludingApplications: ownApplications, exceptingWindows: [])
        case let .window(window):
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
                throw LibreScreenError.sourceUnavailable
            }
            return SCContentFilter(desktopIndependentWindow: scWindow)
        }
    }
}
