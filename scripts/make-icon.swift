// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

// LibreScreen app icon generator. Usage: swift scripts/make-icon.swift <output-dir>
// Draws the 1024×1024 master with Core Graphics and writes every size the macOS asset catalog needs.
import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func makeMaster(size: CGFloat) -> CGImage? {
    guard
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
    let inset = size * 0.075 // macOS icons keep a margin inside the 1024 canvas
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(srgbRed: 0.25, green: 0.33, blue: 0.9, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Gradient background
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [
        CGColor(srgbRed: 0.42, green: 0.36, blue: 1.0, alpha: 1),
        CGColor(srgbRed: 0.18, green: 0.45, blue: 0.98, alpha: 1),
        CGColor(srgbRed: 0.08, green: 0.62, blue: 0.95, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    // Soft highlight
    if let glow = CGGradient(
        colorsSpace: space,
        colors: [CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: rect.midX, y: rect.maxY),
            startRadius: 0,
            endCenter: CGPoint(x: rect.midX, y: rect.maxY),
            endRadius: rect.width * 0.9,
            options: []
        )
    }
    context.restoreGState()

    // Screen glyph
    let screen = CGRect(
        x: rect.minX + rect.width * 0.17,
        y: rect.minY + rect.height * 0.28,
        width: rect.width * 0.66,
        height: rect.height * 0.46
    )
    let screenPath = CGPath(roundedRect: screen, cornerWidth: rect.width * 0.045, cornerHeight: rect.width * 0.045, transform: nil)
    context.saveGState()
    context.setShadow(offset: .zero, blur: size * 0.02, color: CGColor(gray: 0, alpha: 0.25))
    context.addPath(screenPath)
    context.setFillColor(CGColor(gray: 1, alpha: 0.16))
    context.fillPath()
    context.restoreGState()
    context.addPath(screenPath)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
    context.setLineWidth(size * 0.035)
    context.strokePath()
    // Stand
    let standWidth = screen.width * 0.26
    let stand = CGRect(x: screen.midX - standWidth / 2, y: screen.minY - rect.height * 0.085, width: standWidth, height: size * 0.035)
    context.setFillColor(CGColor(gray: 1, alpha: 0.92))
    context.fill(stand)
    context.fill(CGRect(x: screen.midX - size * 0.0175, y: stand.maxY, width: size * 0.035, height: screen.minY - stand.maxY))

    // Record dot
    let dotRadius = rect.width * 0.085
    let dotCenter = CGPoint(x: screen.maxX - dotRadius * 0.4, y: screen.minY + dotRadius * 0.4)
    context.saveGState()
    context.setShadow(offset: .zero, blur: size * 0.025, color: CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 0.6))
    context.setFillColor(CGColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1))
    context.fillEllipse(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    context.restoreGState()
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    context.setLineWidth(size * 0.022)
    context.strokeEllipse(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

    return context.makeImage()
}

func write(_ image: CGImage, size: Int, to url: URL) throws {
    let scaled = NSImage(cgImage: image, size: NSSize(width: size, height: size))
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    scaled.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

guard let master = makeMaster(size: 1024) else { fatalError("could not draw icon") }
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in sizes {
    try write(master, size: size, to: outputDirectory.appendingPathComponent(name))
}

print("icons written to \(outputDirectory.path)")
