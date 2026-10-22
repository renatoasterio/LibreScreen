// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics

/// The only place that converts between ScreenCaptureKit's global space (points, origin at the
/// top-left of the main display) and AppKit's (points, origin at the bottom-left of the main display).
enum CaptureCoordinates {
    /// Converts a top-left-origin global rect to AppKit's bottom-left-origin space.
    static func appKitRect(fromGlobal rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts an AppKit bottom-left-origin rect to the top-left-origin global space.
    static func globalRect(fromAppKit rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a global rect into a display's local space (top-left origin).
    static func localRect(_ rect: CGRect, in display: DisplayInfo) -> CGRect {
        rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    /// The display that contains the largest part of `rect`.
    static func display(containing rect: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays
            .map { display -> (DisplayInfo, CGFloat) in
                let intersection = display.frame.intersection(rect)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                return (display, area)
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Rounds a rect to whole points so captures never straddle a pixel boundary.
    static func integral(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX.rounded(.down),
            y: rect.minY.rounded(.down),
            width: rect.width.rounded(.up),
            height: rect.height.rounded(.up)
        )
    }
}
