// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import CoreImage
import Metal

/// Draws the latest screen frame plus the webcam bubble into a pool pixel buffer with Core Image on
/// Metal. Pure rendering: no state besides cached artwork, called only from the pipeline queue.
final class FrameCompositor {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private var artworkCache: [OverlayArtwork.Key: OverlayArtwork] = [:]

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false, .name: "LibreScreen.compositor"]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    func compose(
        screen: ScreenFrame,
        camera: CameraFrame?,
        overlay: CameraOverlaySettings?,
        outputSize: CGSize,
        into target: CVPixelBuffer
    ) {
        let bounds = CGRect(origin: .zero, size: outputSize)
        var image = Self.fitted(screen: screen, to: outputSize)
        if let camera, let overlay {
            image = composite(camera: camera, overlay: overlay, outputSize: outputSize, over: image)
        }
        // Guarantee every pixel is written, even when the content is letterboxed.
        image = image.composited(over: CIImage(color: .black).cropped(to: bounds))
        context.render(image, to: target, bounds: bounds, colorSpace: colorSpace)
    }

    /// Crops the buffer to its content region and scales it to fit the output, centred.
    private static func fitted(screen: ScreenFrame, to outputSize: CGSize) -> CIImage {
        let pixelRect = screen.contentPixelRect
        let bufferHeight = screen.bufferSize.height
        // Core Image uses a bottom-left origin; the content rect is top-left based.
        let ciRect = CGRect(x: pixelRect.minX, y: bufferHeight - pixelRect.maxY, width: pixelRect.width, height: pixelRect.height)
        var image = CIImage(cvPixelBuffer: screen.pixelBuffer)
            .cropped(to: ciRect)
            .transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
        guard pixelRect.size != outputSize else { return image }

        let scale = min(outputSize.width / pixelRect.width, outputSize.height / pixelRect.height)
        let scaledSize = CGSize(width: pixelRect.width * scale, height: pixelRect.height * scale)
        let offset = CGPoint(
            x: ((outputSize.width - scaledSize.width) / 2).rounded(.down),
            y: ((outputSize.height - scaledSize.height) / 2).rounded(.down)
        )
        image = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
        return image
    }

    private func composite(camera: CameraFrame, overlay: CameraOverlaySettings, outputSize: CGSize, over background: CIImage) -> CIImage {
        let topLeftRect = overlay.overlayRect(in: outputSize)
        guard topLeftRect.width > 1 else { return background }
        let rect = CGRect(
            x: topLeftRect.minX,
            y: outputSize.height - topLeftRect.maxY,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
        let artwork = artwork(for: overlay, side: rect.width)

        // Aspect-fill the camera into the bubble square.
        let extent = camera.image.extent
        let cropSide = min(extent.width, extent.height)
        guard cropSide > 0 else { return background }
        let crop = CGRect(x: extent.midX - cropSide / 2, y: extent.midY - cropSide / 2, width: cropSide, height: cropSide)
        let scale = rect.width / cropSide
        let mask = artwork.mask.transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        let bubble = camera.image
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: rect)

        let decorationOrigin = CGAffineTransform(translationX: rect.minX - artwork.margin, y: rect.minY - artwork.margin)
        var result = background
        if let shadow = artwork.shadow {
            result = shadow.transformed(by: decorationOrigin).composited(over: result)
        }
        result = bubble.composited(over: result)
        if let ring = artwork.ring {
            result = ring.transformed(by: decorationOrigin).composited(over: result)
        }
        return result
    }

    private func artwork(for overlay: CameraOverlaySettings, side: CGFloat) -> OverlayArtwork {
        let key = OverlayArtwork.Key(
            side: Int(side),
            radius: Int(overlay.cornerRadius(forSide: side)),
            border: overlay.showsBorder,
            shadow: overlay.showsShadow
        )
        if let cached = artworkCache[key] {
            return cached
        }
        let artwork = OverlayArtwork.make(key: key)
        if artworkCache.count > 8 {
            artworkCache.removeAll()
        }
        artworkCache[key] = artwork
        return artwork
    }
}

/// Mask, shadow and border for the bubble, rasterised once per size with Core Graphics.
struct OverlayArtwork {
    struct Key: Hashable {
        let side: Int
        let radius: Int
        let border: Bool
        let shadow: Bool
    }

    /// White rounded shape with alpha, `side` × `side`.
    let mask: CIImage
    /// Soft drop shadow on a canvas of `side + 2 × margin`, or `nil`.
    let shadow: CIImage?
    /// Hairline ring on the same canvas as the shadow, or `nil`.
    let ring: CIImage?
    let margin: CGFloat

    static func make(key: Key) -> OverlayArtwork {
        let side = CGFloat(key.side)
        let radius = CGFloat(key.radius)
        let margin = (side * 0.14).rounded(.up)
        let canvas = side + margin * 2
        let shapeInCanvas = CGRect(x: margin, y: margin, width: side, height: side)

        let mask = draw(size: CGSize(width: side, height: side)) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.addPath(CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            ))
            context.fillPath()
        }

        let shadow: CIImage? = key.shadow ? draw(size: CGSize(width: canvas, height: canvas)) { context in
            context.setShadow(offset: CGSize(width: 0, height: -side * 0.03), blur: side * 0.08, color: CGColor(gray: 0, alpha: 0.45))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.addPath(CGPath(roundedRect: shapeInCanvas, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        } : nil

        let ring: CIImage? = key.border ? draw(size: CGSize(width: canvas, height: canvas)) { context in
            let width = max(2, side * 0.014)
            let inset = shapeInCanvas.insetBy(dx: width / 2, dy: width / 2)
            context.setLineWidth(width)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
            context.addPath(CGPath(
                roundedRect: inset,
                cornerWidth: max(radius - width / 2, 0),
                cornerHeight: max(radius - width / 2, 0),
                transform: nil
            ))
            context.strokePath()
        } : nil

        return OverlayArtwork(mask: mask, shadow: shadow, ring: ring, margin: margin)
    }

    private static func draw(size: CGSize, _ body: (CGContext) -> Void) -> CIImage {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return CIImage.empty() }
        body(context)
        guard let image = context.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: image)
    }
}
