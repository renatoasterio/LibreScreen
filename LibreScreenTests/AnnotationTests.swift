// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Testing
@testable import LibreScreen

struct AnnotationTests {
    private let style = AnnotationStyle()

    @Test func arrowHitTestUsesDistanceToSegment() {
        let arrow = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), style: style)
        #expect(arrow.contains(CGPoint(x: 50, y: 3), tolerance: 2))
        #expect(!arrow.contains(CGPoint(x: 50, y: 30), tolerance: 2))
        #expect(!arrow.contains(CGPoint(x: 160, y: 0), tolerance: 2))
    }

    @Test func ellipseHitTestIsElliptical() {
        let ellipse = Annotation(shape: .ellipse(CGRect(x: 0, y: 0, width: 100, height: 50)), style: style)
        #expect(ellipse.contains(CGPoint(x: 50, y: 25), tolerance: 0))
        #expect(!ellipse.contains(CGPoint(x: 2, y: 2), tolerance: 0))
    }

    @Test func translateMovesEveryShape() {
        var rect = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), style: style)
        rect.translate(by: CGPoint(x: 5, y: -5))
        #expect(rect.shape == .rectangle(CGRect(x: 15, y: 5, width: 20, height: 20)))

        var path = Annotation(shape: .freehand([.zero, CGPoint(x: 1, y: 1)]), style: style)
        path.translate(by: CGPoint(x: 1, y: 1))
        #expect(path.shape == .freehand([CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]))
    }

    @Test func documentNumbersIncrementAndCropClamps() {
        var document = AnnotationDocument(imageSize: CGSize(width: 200, height: 100))
        document.add(Annotation(shape: .number(document.nextNumber, center: .zero), style: style))
        document.add(Annotation(shape: .number(document.nextNumber, center: .zero), style: style))
        #expect(document.nextNumber == 3)

        document.applyCrop(CGRect(x: -10, y: 20, width: 500, height: 30))
        #expect(document.cropRect == CGRect(x: 0, y: 20, width: 200, height: 30))
        #expect(document.visibleRect.height == 30)
    }

    @Test func topmostAnnotationWinsHitTest() {
        var document = AnnotationDocument(imageSize: CGSize(width: 100, height: 100))
        let bottom = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)), style: style)
        let top = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)), style: style)
        document.add(bottom)
        document.add(top)
        #expect(document.annotation(at: CGPoint(x: 10, y: 10), tolerance: 1)?.id == top.id)
        document.remove(id: top.id)
        #expect(document.annotation(at: CGPoint(x: 10, y: 10), tolerance: 1)?.id == bottom.id)
    }

    @Test func rendererProducesCroppedImage() {
        let base = makeImage(width: 40, height: 30)
        var document = AnnotationDocument(imageSize: CGSize(width: 40, height: 30))
        document.add(Annotation(shape: .rectangle(CGRect(x: 2, y: 2, width: 10, height: 10)), style: style))
        document.applyCrop(CGRect(x: 10, y: 5, width: 20, height: 20))
        let rendered = AnnotationRenderer.render(document: document, base: base)
        #expect(rendered?.width == 20)
        #expect(rendered?.height == 20)
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // swiftlint:disable:next force_unwrapping
        return context!.makeImage()!
    }
}
