// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreImage
import CoreMedia
import CoreVideo

/// One frame from ScreenCaptureKit. The pixel buffer is never mutated after creation, which is what
/// the unchecked `Sendable` relies on; consumers only read it.
struct ScreenFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    /// Region of the buffer that holds content, in points (window captures shrink when the window does).
    let contentRect: CGRect
    /// Points → pixels for the content.
    let scaleFactor: CGFloat
    /// Extra scaling ScreenCaptureKit applied to fit the content into the buffer.
    let contentScale: CGFloat

    var bufferSize: CGSize {
        CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
    }

    /// The content region in pixels, clamped to the buffer.
    var contentPixelRect: CGRect {
        let factor = scaleFactor * contentScale
        let rect = CGRect(
            x: contentRect.minX * factor,
            y: contentRect.minY * factor,
            width: contentRect.width * factor,
            height: contentRect.height * factor
        )
        let clamped = rect.intersection(CGRect(origin: .zero, size: bufferSize))
        return clamped.isNull || clamped.isEmpty ? CGRect(origin: .zero, size: bufferSize) : clamped.integral
    }
}

/// One processed webcam frame (blur and mirroring already applied). `CIImage` is immutable.
struct CameraFrame: @unchecked Sendable {
    let image: CIImage
    let presentationTime: CMTime

    var size: CGSize {
        image.extent.size
    }
}

/// Where the pipeline and the preview bubble read webcam frames from.
protocol CameraFrameSource: AnyObject, Sendable {
    /// The most recent frame, or `nil` when the camera is off.
    var latestFrame: CameraFrame? { get }
    /// A stream that only ever holds the newest frame, so slow consumers never back-pressure capture.
    func frames() -> AsyncStream<CameraFrame>
}

/// Carries an audio `CMSampleBuffer` across queues. Buffers are never mutated after capture.
struct SampleBufferBox: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

/// Receives screen frames and system audio from `ScreenCaptureEngine` on its delivery queues.
protocol ScreenFrameSink: AnyObject, Sendable {
    func screenCapture(didOutput frame: ScreenFrame)
    func screenCapture(didOutputAudio sampleBuffer: CMSampleBuffer)
    func screenCapture(didStopWith error: any Error)
}

/// Receives microphone buffers from `MicrophoneCaptureService` on its delivery queue.
protocol MicrophoneSampleSink: AnyObject, Sendable {
    func microphone(didOutput sampleBuffer: CMSampleBuffer)
}
