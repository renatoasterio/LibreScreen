// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

#if DEBUG
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreVideo
import Foundation
import Synchronization

/// Debug-only stand-in for the webcam: a moving test pattern at 30 fps, optionally run through the
/// real `CameraBackgroundProcessor`. Lets the compositing path be exercised without a camera permission.
final class SyntheticCameraSource: CameraFrameSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "br.com.asoft.LibreScreen.synthetic-camera")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let processor = CameraBackgroundProcessor()
    private let size = CGSize(width: 1280, height: 720)
    private var pool: CVPixelBufferPool?
    private var timer: DispatchSourceTimer?
    private var frameIndex = 0
    private let options: CameraProcessingOptions
    private let latest = Mutex<CameraFrame?>(nil)
    private var continuations: [UUID: AsyncStream<CameraFrame>.Continuation] = [:]

    init(background: CameraBackgroundMode, backgroundImageURL: URL? = nil) {
        options = CameraProcessingOptions(
            background: background,
            backgroundImageURL: backgroundImageURL,
            blurIntensity: 0.6,
            mirrored: false
        )
    }

    var latestFrame: CameraFrame? {
        latest.withLock { $0 }
    }

    func frames() -> AsyncStream<CameraFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            queue.async { [weak self] in self?.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.queue.async { [weak self] in self?.continuations[id] = nil }
            }
        }
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in self?.produce() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func produce() {
        frameIndex += 1
        let phase = CGFloat(frameIndex % 90) / 90
        let gradient = CIFilter.linearGradient()
        gradient.point0 = .zero
        gradient.point1 = CGPoint(x: size.width, y: size.height)
        gradient.color0 = CIColor(red: 0.95, green: 0.55, blue: 0.2)
        gradient.color1 = CIColor(red: 0.2, green: 0.4, blue: 0.95)
        let circle = CIFilter.radialGradient()
        circle.center = CGPoint(x: size.width * (0.2 + 0.6 * phase), y: size.height / 2)
        circle.radius0 = 120
        circle.radius1 = 125
        circle.color0 = CIColor(red: 1, green: 1, blue: 1)
        circle.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let bounds = CGRect(origin: .zero, size: size)
        guard let background = gradient.outputImage?.cropped(to: bounds), let dot = circle.outputImage?.cropped(to: bounds) else { return }
        var image = dot.composited(over: background)
        guard let buffer = pooledBuffer() else { return }
        context.render(image, to: buffer, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        image = CIImage(cvPixelBuffer: buffer)
        if options.background != .none {
            image = processor.process(image, pixelBuffer: buffer, options: options)
            guard let processed = pooledBuffer() else { return }
            context.render(image, to: processed, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            image = CIImage(cvPixelBuffer: processed)
        }
        let frame = CameraFrame(image: image, presentationTime: CMClockGetTime(CMClockGetHostTimeClock()))
        latest.withLock { $0 = frame }
        for continuation in continuations.values {
            continuation.yield(frame)
        }
    }

    private func pooledBuffer() -> CVPixelBuffer? {
        if pool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
#endif
