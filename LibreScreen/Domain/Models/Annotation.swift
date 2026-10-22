// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case arrow
    case line
    case rectangle
    case ellipse
    case freehand
    case text
    case highlighter
    case pixelate
    case number
    case crop

    var id: String {
        rawValue
    }

    /// Tools that create an annotation by dragging.
    var createsAnnotation: Bool {
        switch self {
        case .select, .crop: false
        default: true
        }
    }
}

/// Framework-free colour so the Domain never imports AppKit or SwiftUI.
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let red = RGBAColor(red: 1.0, green: 0.23, blue: 0.19)
    static let orange = RGBAColor(red: 1.0, green: 0.58, blue: 0.0)
    static let yellow = RGBAColor(red: 1.0, green: 0.84, blue: 0.04)
    static let green = RGBAColor(red: 0.2, green: 0.78, blue: 0.35)
    static let blue = RGBAColor(red: 0.0, green: 0.48, blue: 1.0)
    static let purple = RGBAColor(red: 0.69, green: 0.32, blue: 0.87)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0.1, green: 0.1, blue: 0.1)

    static let presets: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
}

struct AnnotationStyle: Codable, Hashable, Sendable {
    var color: RGBAColor = .red
    var lineWidth: CGFloat = 4
    var isFilled = false
    var fontSize: CGFloat = 28

    static let lineWidths: [CGFloat] = [2, 4, 6, 10]
    static let fontSizes: [CGFloat] = [18, 28, 40, 56]
}

/// Geometry in image pixel space, top-left origin.
enum AnnotationShape: Codable, Equatable, Sendable {
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case freehand([CGPoint])
    case highlighter([CGPoint])
    case text(String, origin: CGPoint)
    case pixelate(CGRect)
    case number(Int, center: CGPoint)
}

struct Annotation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var shape: AnnotationShape
    var style: AnnotationStyle

    init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle) {
        self.id = id
        self.shape = shape
        self.style = style
    }

    /// Bounding box in image pixels (text uses an estimate; the renderer measures precisely).
    var bounds: CGRect {
        switch shape {
        case let .arrow(from, to), let .line(from, to):
            return Self.rect(from: from, to: to).insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case let .rectangle(rect), let .ellipse(rect), let .pixelate(rect):
            return rect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case let .freehand(points), let .highlighter(points):
            return Self.rect(containing: points).insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case let .text(text, origin):
            let width = CGFloat(max(text.count, 1)) * style.fontSize * 0.6
            return CGRect(x: origin.x, y: origin.y, width: width, height: style.fontSize * 1.3)
        case let .number(_, center):
            let radius = style.fontSize * 0.8
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch shape {
        case let .arrow(from, to), let .line(from, to):
            return Self.distance(from: point, toSegment: (from, to)) <= tolerance + style.lineWidth
        case let .rectangle(rect), let .pixelate(rect):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .ellipse(rect):
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            guard outer.width > 0, outer.height > 0 else { return false }
            let dx = (point.x - outer.midX) / (outer.width / 2)
            let dy = (point.y - outer.midY) / (outer.height / 2)
            return dx * dx + dy * dy <= 1
        case let .freehand(points), let .highlighter(points):
            guard points.count > 1 else { return bounds.contains(point) }
            return zip(points, points.dropFirst()).contains { Self.distance(from: point, toSegment: $0) <= tolerance + style.lineWidth }
        case .text, .number:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    mutating func translate(by offset: CGPoint) {
        switch shape {
        case let .arrow(from, to):
            shape = .arrow(from: from + offset, to: to + offset)
        case let .line(from, to):
            shape = .line(from: from + offset, to: to + offset)
        case let .rectangle(rect):
            shape = .rectangle(rect.offsetBy(dx: offset.x, dy: offset.y))
        case let .ellipse(rect):
            shape = .ellipse(rect.offsetBy(dx: offset.x, dy: offset.y))
        case let .pixelate(rect):
            shape = .pixelate(rect.offsetBy(dx: offset.x, dy: offset.y))
        case let .freehand(points):
            shape = .freehand(points.map { $0 + offset })
        case let .highlighter(points):
            shape = .highlighter(points.map { $0 + offset })
        case let .text(text, origin):
            shape = .text(text, origin: origin + offset)
        case let .number(value, center):
            shape = .number(value, center: center + offset)
        }
    }

    static func rect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
    }

    static func rect(containing points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func distance(from point: CGPoint, toSegment segment: (CGPoint, CGPoint)) -> CGFloat {
        let (start, end) = segment
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let ratio = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + ratio * dx, y: start.y + ratio * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

/// Everything the editor edits: the crop and the annotations over one image.
struct AnnotationDocument: Equatable, Sendable {
    var imageSize: CGSize
    var cropRect: CGRect?
    var annotations: [Annotation] = []
    var nextNumber = 1

    init(imageSize: CGSize) {
        self.imageSize = imageSize
    }

    /// The visible area: the crop when set, otherwise the whole image.
    var visibleRect: CGRect {
        cropRect ?? CGRect(origin: .zero, size: imageSize)
    }

    mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
        if case .number = annotation.shape {
            nextNumber += 1
        }
    }

    mutating func remove(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    func annotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.reversed().first { $0.contains(point, tolerance: tolerance) }
    }

    /// Applies the crop permanently: annotations move with the content and the canvas shrinks.
    mutating func applyCrop(_ rect: CGRect) {
        let clamped = rect.intersection(CGRect(origin: .zero, size: imageSize)).integral
        guard clamped.width >= 1, clamped.height >= 1 else { return }
        cropRect = clamped
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}
