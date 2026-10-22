// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import CoreText
import Foundation

/// Draws annotations with Core Graphics in image pixel space (top-left origin). The same code paints
/// the live canvas and the exported file, so what you see is what you save.
enum AnnotationRenderer {
    /// Draws into a context whose coordinate system already matches image pixels with a top-left origin.
    static func draw(_ annotations: [Annotation], base: CGImage?, in context: CGContext) {
        for annotation in annotations {
            context.saveGState()
            draw(annotation, base: base, in: context)
            context.restoreGState()
        }
    }

    /// The final image: crop applied, annotations burned in, at the original pixel scale.
    static func render(document: AnnotationDocument, base: CGImage) -> CGImage? {
        let visible = document.visibleRect
        let width = Int(visible.width), height = Int(visible.height)
        guard
            width > 0, height > 0,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return nil }
        // Flip to a top-left origin and shift so the crop's origin lands at (0, 0).
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -visible.minX, y: -visible.minY)
        drawBase(base, in: context)
        draw(document.annotations, base: base, in: context)
        return context.makeImage()
    }

    /// Draws the base image in a top-left-origin context (`CGImage` is bottom-up, so flip locally).
    static func drawBase(_ image: CGImage, in context: CGContext) {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.saveGState()
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }

    // MARK: - Shapes

    private static func draw(_ annotation: Annotation, base: CGImage?, in context: CGContext) {
        let style = annotation.style
        let color = cgColor(style.color)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(style.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.shape {
        case let .line(from, to):
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        case let .arrow(from, to):
            drawArrow(from: from, to: to, lineWidth: style.lineWidth, in: context)
        case let .rectangle(rect):
            let path = CGPath(roundedRect: rect, cornerWidth: style.lineWidth, cornerHeight: style.lineWidth, transform: nil)
            context.addPath(path)
            fillOrStroke(filled: style.isFilled, in: context)
        case let .ellipse(rect):
            context.addEllipse(in: rect)
            fillOrStroke(filled: style.isFilled, in: context)
        case let .freehand(points):
            stroke(points, in: context)
        case let .highlighter(points):
            context.setStrokeColor(cgColor(style.color, alpha: 0.35))
            context.setLineWidth(style.lineWidth * 4)
            context.setBlendMode(.multiply)
            stroke(points, in: context)
        case let .text(text, origin):
            drawText(text, at: origin, fontSize: style.fontSize, color: color, in: context)
        case let .pixelate(rect):
            if let base {
                drawPixelated(rect, base: base, in: context)
            }
        case let .number(value, center):
            drawNumber(value, at: center, style: style, in: context)
        }
    }

    private static func fillOrStroke(filled: Bool, in context: CGContext) {
        if filled {
            context.fillPath()
        } else {
            context.strokePath()
        }
    }

    private static func stroke(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        if points.count == 1 {
            context.addLine(to: first)
        }
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, in context: CGContext) {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0.5 else { return }
        let headLength = max(lineWidth * 4, 14)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let shaftEnd = CGPoint(x: to.x - cos(angle) * headLength * 0.6, y: to.y - sin(angle) * headLength * 0.6)
        context.move(to: from)
        context.addLine(to: shaftEnd)
        context.strokePath()
        let spread: CGFloat = .pi / 7
        let left = CGPoint(x: to.x - cos(angle - spread) * headLength, y: to.y - sin(angle - spread) * headLength)
        let right = CGPoint(x: to.x - cos(angle + spread) * headLength, y: to.y - sin(angle + spread) * headLength)
        context.move(to: to)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.fillPath()
    }

    private static func drawText(_ text: String, at origin: CGPoint, fontSize: CGFloat, color: CGColor, in context: CGContext) {
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
        let ascent = CTFontGetAscent(font)
        // CoreText draws bottom-up; flip locally around the baseline.
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: origin.x, y: origin.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.45))
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawNumber(_ value: Int, at center: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let radius = style.fontSize * 0.8
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: CGColor(gray: 0, alpha: 0.35))
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.setShadow(offset: .zero, blur: 0, color: nil)
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, style.fontSize, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "\(value)" as CFString, attributes as CFDictionary))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: center.x - bounds.midX, y: center.y + bounds.midY)
        context.scaleBy(x: 1, y: -1)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Mosaic: downsample the region with nearest-neighbour and draw it back enlarged.
    private static func drawPixelated(_ rect: CGRect, base: CGImage, in context: CGContext) {
        let region = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard region.width >= 2, region.height >= 2, let cropped = base.cropping(to: region) else { return }
        let block = max(8, Int(min(region.width, region.height) / 12))
        let smallWidth = max(Int(region.width) / block, 1)
        let smallHeight = max(Int(region.height) / block, 1)
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let small = CGContext(
                data: nil,
                width: smallWidth,
                height: smallHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return }
        small.interpolationQuality = .none
        small.draw(cropped, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let mosaic = small.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.translateBy(x: region.minX, y: region.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(mosaic, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
        context.restoreGState()
    }

    static func cgColor(_ color: RGBAColor, alpha: Double? = nil) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha ?? color.alpha)
    }
}
