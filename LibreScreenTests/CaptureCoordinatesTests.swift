// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Testing
@testable import LibreScreen

struct CaptureCoordinatesTests {
    private let main = DisplayInfo(
        id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scaleFactor: 1, isMain: true
    )
    private let second = DisplayInfo(
        id: 2, name: "Second", frame: CGRect(x: 1920, y: -200, width: 1512, height: 982), scaleFactor: 2, isMain: false
    )

    @Test func globalToAppKitFlipsVertically() {
        let global = CGRect(x: 10, y: 20, width: 100, height: 50)
        let appKit = CaptureCoordinates.appKitRect(fromGlobal: global, mainDisplayHeight: 1080)
        #expect(appKit == CGRect(x: 10, y: 1010, width: 100, height: 50))
        #expect(CaptureCoordinates.globalRect(fromAppKit: appKit, mainDisplayHeight: 1080) == global)
    }

    @Test func localRectIsRelativeToTheDisplayOrigin() {
        let global = CGRect(x: 2000, y: -100, width: 300, height: 200)
        let local = CaptureCoordinates.localRect(global, in: second)
        #expect(local == CGRect(x: 80, y: 100, width: 300, height: 200))
    }

    @Test func displayContainingPicksTheLargestOverlap() {
        let straddling = CGRect(x: 1800, y: 100, width: 400, height: 300)
        #expect(CaptureCoordinates.display(containing: straddling, in: [main, second])?.id == 2)
        let outside = CGRect(x: -5000, y: -5000, width: 10, height: 10)
        #expect(CaptureCoordinates.display(containing: outside, in: [main, second]) == nil)
    }

    @Test func integralExpandsToWholePoints() {
        let rect = CGRect(x: 1.4, y: 2.6, width: 10.2, height: 5.5)
        let integral = CaptureCoordinates.integral(rect)
        #expect(integral == CGRect(x: 1, y: 2, width: 11, height: 6))
    }
}
