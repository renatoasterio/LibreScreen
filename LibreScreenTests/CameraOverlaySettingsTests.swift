// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Testing
@testable import LibreScreen

struct CameraOverlaySettingsTests {
    @Test func bottomRightBubbleSitsInsideTheFrame() {
        var settings = CameraOverlaySettings()
        settings.size = .medium
        settings.corner = .bottomRight
        let frame = CGSize(width: 1920, height: 1080)
        let rect = settings.overlayRect(in: frame)
        #expect(rect.maxX <= frame.width)
        #expect(rect.maxY <= frame.height)
        #expect(rect.width == rect.height)
        #expect(rect.height == (1080 * OverlaySize.medium.fractionOfHeight).rounded(.down))
    }

    @Test func topLeftBubbleStartsAtTheMargin() {
        var settings = CameraOverlaySettings()
        settings.corner = .topLeft
        let rect = settings.overlayRect(in: CGSize(width: 1000, height: 1000))
        let margin = (1000 * CameraOverlaySettings.marginFraction).rounded(.down)
        #expect(rect.minX == margin)
        #expect(rect.minY == margin)
    }

    @Test func blurIntensityIsClamped() {
        var settings = CameraOverlaySettings()
        settings.blurIntensity = 7
        #expect(settings.validated().blurIntensity == 1)
        settings.blurIntensity = -1
        #expect(settings.validated().blurIntensity == 0)
    }

    @Test func circleRadiusIsHalfTheSide() {
        var settings = CameraOverlaySettings()
        settings.shape = .circle
        #expect(settings.cornerRadius(forSide: 200) == 100)
        settings.shape = .roundedRectangle
        #expect(settings.cornerRadius(forSide: 200) < 100)
    }
}
