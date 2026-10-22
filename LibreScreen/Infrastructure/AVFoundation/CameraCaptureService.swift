// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AVFoundation
import CoreImage
import Metal
import Synchronization

/// Webcam capture with on-queue processing (blur, mirror) rendered into pooled pixel buffers, so the
/// preview bubble and the compositor sample exactly the same pixels. Session state is confined to the
/// capture queue; the latest frame and the preview streams sit behind mutexes.
final class CameraCaptureService: NSObject, CameraCapturing, CameraFrameSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "br.com.asoft.LibreScreen.camera", qos: .userInteractive)
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let blur = BackgroundBlurProcessor()
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private var input: AVCaptureDeviceInput?
    private var options = CameraProcessingOptions(blurEnabled: false, blurIntensity: 0, mirrored: true)
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    private let latest = Mutex<CameraFrame?>(nil)
    private let continuations = Mutex<[UUID: AsyncStream<CameraFrame>.Continuation]>([:])

    override init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false, .name: "LibreScreen.camera"]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
        super.init()
    }

    // MARK: - CameraFrameSource

    var latestFrame: CameraFrame? {
        latest.withLock { $0 }
    }

    func frames() -> AsyncStream<CameraFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            continuations.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.continuations.withLock { $0[id] = nil }
            }
        }
    }

    // MARK: - CameraCapturing

    var isRunning: Bool {
        get async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                queue.async { [weak self] in
                    continuation.resume(returning: self?.session.isRunning ?? false)
                }
            }
        }
    }

    func start(deviceID: String?, options: CameraProcessingOptions) async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw LibreScreenError.permissionDenied(.camera)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // lifetime: bounded by the continuation.
            queue.async { [self] in
                do {
                    try configure(deviceID: deviceID)
                    self.options = options
                    blur.reset()
                    session.startRunning()
                    Log.camera.info("Camera started")
                    continuation.resume()
                } catch let error as LibreScreenError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: LibreScreenError.cameraUnavailable)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // lifetime: bounded by the continuation.
            queue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                session.beginConfiguration()
                if let input {
                    session.removeInput(input)
                }
                session.removeOutput(output)
                session.commitConfiguration()
                input = nil
                latest.withLock { $0 = nil }
                Log.camera.info("Camera stopped")
                continuation.resume()
            }
        }
    }

    func updateProcessing(_ options: CameraProcessingOptions) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                self?.options = options
                continuation.resume()
            }
        }
    }

    // MARK: - Queue-confined

    private func configure(deviceID: String?) throws {
        // Resolved here because AVCaptureDevice is not Sendable.
        let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw LibreScreenError.cameraUnavailable }
        let deviceInput = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let input {
            session.removeInput(input)
        }
        session.removeOutput(output)
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        guard session.canAddInput(deviceInput), session.canAddOutput(output) else {
            throw LibreScreenError.cameraUnavailable
        }
        session.addInput(deviceInput)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        input = deviceInput
    }

    private func pooledBuffer(for size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            var newPool: CVPixelBufferPool?
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(
                nil,
                [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary,
                attributes as CFDictionary,
                &newPool
            )
            pool = newPool
            poolSize = size
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private func publish(_ frame: CameraFrame) {
        latest.withLock { $0 = frame }
        let active = continuations.withLock { Array($0.values) }
        for continuation in active {
            continuation.yield(frame)
        }
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        autoreleasepool {
            var image = CIImage(cvPixelBuffer: pixelBuffer)
            let extent = image.extent
            if options.blurEnabled {
                image = blur.process(image, pixelBuffer: pixelBuffer, intensity: options.blurIntensity)
            }
            if options.mirrored {
                image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -extent.width, y: 0))
            }
            guard let target = pooledBuffer(for: extent.size) else { return }
            context.render(image, to: target, bounds: CGRect(origin: .zero, size: extent.size), colorSpace: colorSpace)
            publish(CameraFrame(image: CIImage(cvPixelBuffer: target), presentationTime: sampleBuffer.presentationTimeStamp))
        }
    }
}
