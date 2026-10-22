// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

/// Person segmentation (Vision, on device) + Gaussian blur of everything that is not the person.
/// Called only from the camera queue. Falls back to the previous mask when a frame cannot be
/// segmented and lowers quality automatically when segmentation is slower than a frame.
final class BackgroundBlurProcessor {
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

    func process(_ image: CIImage, pixelBuffer: CVPixelBuffer, intensity: Double) -> CIImage {
        let mask = segment(pixelBuffer, matching: image.extent) ?? previousMask
        guard let mask else { return image }
        previousMask = mask

        let sigma = 4 + intensity * 26
        let blurred = image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: image.extent)
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: mask
        ])
    }

    func reset() {
        previousMask = nil
        maskPool = nil
        slowFrames = 0
        request.qualityLevel = .balanced
    }

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
