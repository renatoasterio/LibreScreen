// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import ImageIO
import Vision

/// Everything that happens to a webcam frame before preview and compositing: person segmentation
/// (Vision, on device), mirroring, and either a Gaussian blur or a replacement image behind the person.
/// Called only from the camera queue. Falls back to the previous mask when a frame cannot be
/// segmented and lowers segmentation quality automatically when it is slower than a frame.
final class CameraBackgroundProcessor {
    static let slowFrameThreshold: TimeInterval = 0.024

    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private let context = CIContext(options: [.cacheIntermediates: false, .name: "LibreScreen.mask"])
    private var previousMask: CIImage?
    private var maskPool: CVPixelBufferPool?
    private var maskPoolSize: CGSize = .zero
    private var slowFrames = 0
    private var backgroundURL: URL?
    private var backgroundSource: CIImage?
    private var backgroundFitted: (size: CGSize, image: CIImage)?

    func process(_ image: CIImage, pixelBuffer: CVPixelBuffer, options: CameraProcessingOptions) -> CIImage {
        let extent = image.extent
        let mode = effectiveMode(options)
        guard mode != .none else { return mirrored(image, if: options.mirrored, extent: extent) }

        let mask = segment(pixelBuffer, matching: extent) ?? previousMask
        guard let mask else { return mirrored(image, if: options.mirrored, extent: extent) }
        previousMask = mask

        // The person (and its mask) is mirrored; a replacement background keeps its own orientation.
        let person = mirrored(image, if: options.mirrored, extent: extent)
        let personMask = mirrored(mask, if: options.mirrored, extent: extent)
        let background: CIImage = switch mode {
        case .blur:
            person
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 4 + options.blurIntensity * 26)
                .cropped(to: extent)
        case .image:
            fittedBackground(for: extent.size) ?? person
        case .none:
            person
        }
        return person.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: personMask
        ])
    }

    func reset() {
        previousMask = nil
        maskPool = nil
        slowFrames = 0
        request.qualityLevel = .balanced
    }

    /// Image mode without a loadable image falls back to blur so the room never shows unexpectedly.
    private func effectiveMode(_ options: CameraProcessingOptions) -> CameraBackgroundMode {
        guard options.background == .image else { return options.background }
        return loadBackgroundIfNeeded(options.backgroundImageURL) ? .image : .blur
    }

    private func mirrored(_ image: CIImage, if enabled: Bool, extent: CGRect) -> CIImage {
        guard enabled else { return image }
        return image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -(extent.minX * 2 + extent.width), y: 0))
    }

    // MARK: - Replacement image

    private func loadBackgroundIfNeeded(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url == backgroundURL, backgroundSource != nil {
            return true
        }
        backgroundURL = url
        backgroundFitted = nil
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            backgroundSource = nil
            Log.camera.error("Background image could not be loaded: \(url.lastPathComponent, privacy: .private)")
            return false
        }
        backgroundSource = CIImage(cgImage: cgImage)
        return true
    }

    /// The background aspect-filled to the frame, rendered once into a buffer and reused every frame.
    private func fittedBackground(for size: CGSize) -> CIImage? {
        if let backgroundFitted, backgroundFitted.size == size {
            return backgroundFitted.image
        }
        guard let backgroundSource, size.width > 0, size.height > 0 else { return nil }
        let extent = backgroundSource.extent
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = backgroundSource
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGPoint(x: (size.width - extent.width * scale) / 2, y: (size.height - extent.height * scale) / 2)
        let fitted = scaled.transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y)).cropped(to: CGRect(
            origin: .zero,
            size: size
        ))
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) ==
            kCVReturnSuccess,
            let buffer else { return nil }
        context.render(fitted, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let image = CIImage(cvPixelBuffer: buffer)
        backgroundFitted = (size, image)
        return image
    }

    // MARK: - Segmentation

    private func segment(_ pixelBuffer: CVPixelBuffer, matching extent: CGRect) -> CIImage? {
        let started = CFAbsoluteTimeGetCurrent()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let result = request.results?.first else { return nil }
        adaptQuality(elapsed: CFAbsoluteTimeGetCurrent() - started)

        var mask = CIImage(cvPixelBuffer: result.pixelBuffer)
        let scaleX = extent.width / mask.extent.width
        let scaleY = extent.height / mask.extent.height
        mask = mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .applyingGaussianBlur(sigma: 1.5)
            .cropped(to: extent)
        if let previousMask {
            // Light temporal smoothing hides the flicker of per-frame segmentation.
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = previousMask
            mix.targetImage = mask
            mix.time = 0.7
            mask = mix.outputImage?.cropped(to: extent) ?? mask
        }
        // Materialise the mask: keeping the lazy Core Image graph would chain every previous frame
        // into the next one and grow memory without bound.
        return materialised(mask, size: extent.size) ?? mask
    }

    private func materialised(_ mask: CIImage, size: CGSize) -> CIImage? {
        let target = CGSize(width: max((size.width / 2).rounded(), 1), height: max((size.height / 2).rounded(), 1))
        if maskPool == nil || maskPoolSize != target {
            var pool: CVPixelBufferPool?
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(target.width),
                kCVPixelBufferHeightKey as String: Int(target.height),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            CVPixelBufferPoolCreate(
                nil,
                [kCVPixelBufferPoolMinimumBufferCountKey as String: 2] as CFDictionary,
                attributes as CFDictionary,
                &pool
            )
            maskPool = pool
            maskPoolSize = target
        }
        guard let maskPool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, maskPool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        let scale = target.width / size.width
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: scale, y: target.height / size.height))
        context.render(scaled, to: buffer, bounds: CGRect(origin: .zero, size: target), colorSpace: nil)
        return CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: 1 / scale, y: size.height / target.height))
    }

    private func adaptQuality(elapsed: TimeInterval) {
        guard request.qualityLevel == .balanced else { return }
        slowFrames = elapsed > Self.slowFrameThreshold ? slowFrames + 1 : 0
        if slowFrames >= 15 {
            request.qualityLevel = .fast
            Log.camera.notice("Segmentation too slow, switching to fast quality")
        }
    }
}
