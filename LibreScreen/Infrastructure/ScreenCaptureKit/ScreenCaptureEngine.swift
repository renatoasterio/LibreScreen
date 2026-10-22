// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreMedia
import ScreenCaptureKit

struct ScreenCaptureConfiguration: Sendable {
    let pixelSize: CGSize
    let frameRate: Int
    let showsCursor: Bool
    let capturesAudio: Bool
    /// Display-local points for region captures.
    let sourceRect: CGRect?
    let queueDepth = 5
}

/// Wraps one `SCStream`. Frames and audio go to the sink on dedicated serial queues; nothing here
/// touches the UI. State is confined to the capture queue, hence the unchecked `Sendable`.
final class ScreenCaptureEngine: NSObject, @unchecked Sendable {
    private let videoQueue = DispatchQueue(label: "br.com.asoft.LibreScreen.screen.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "br.com.asoft.LibreScreen.screen.audio", qos: .userInteractive)
    private var stream: SCStream?
    private weak var sink: (any ScreenFrameSink)?

    func start(source: CaptureSource, configuration: ScreenCaptureConfiguration, sink: any ScreenFrameSink) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = try ContentFilterFactory.filter(for: source, content: content)
        let streamConfiguration = Self.makeStreamConfiguration(configuration)
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if configuration.capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        self.sink = sink
        self.stream = stream
        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            throw LibreScreenError.captureFailed(reason: error.localizedDescription)
        }
        let width = Int(configuration.pixelSize.width)
        let height = Int(configuration.pixelSize.height)
        Log.capture.notice("Screen capture started: \(width)×\(height) @\(configuration.frameRate) fps")
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            Log.capture.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
        }
        try? stream.removeStreamOutput(self, type: .screen)
        try? stream.removeStreamOutput(self, type: .audio)
        sink = nil
    }

    private static func makeStreamConfiguration(_ configuration: ScreenCaptureConfiguration) -> SCStreamConfiguration {
        let stream = SCStreamConfiguration()
        stream.width = Int(configuration.pixelSize.width)
        stream.height = Int(configuration.pixelSize.height)
        stream.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        stream.pixelFormat = kCVPixelFormatType_32BGRA
        stream.colorSpaceName = CGColorSpace.sRGB
        stream.showsCursor = configuration.showsCursor
        stream.queueDepth = configuration.queueDepth
        stream.scalesToFit = true
        stream.capturesAudio = configuration.capturesAudio
        stream.sampleRate = 48000
        stream.channelCount = 2
        stream.excludesCurrentProcessAudio = true
        stream.includeChildWindows = true
        stream.captureResolution = .best
        if let rect = configuration.sourceRect {
            stream.sourceRect = rect
        }
        return stream
    }
}

extension ScreenCaptureEngine: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard let frame = Self.screenFrame(from: sampleBuffer) else { return }
            sink?.screenCapture(didOutput: frame)
        case .audio:
            sink?.screenCapture(didOutputAudio: sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Log.capture.error("Stream stopped: \(error.localizedDescription, privacy: .public)")
        sink?.screenCapture(didStopWith: error)
    }

    /// Only complete frames carry new pixels; idle/blank frames are dropped so the compositor keeps the last good one.
    private static func screenFrame(from sampleBuffer: CMSampleBuffer) -> ScreenFrame? {
        guard
            sampleBuffer.isValid,
            let pixelBuffer = sampleBuffer.imageBuffer,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let info = attachments.first,
            let statusValue = info[.status] as? Int,
            SCFrameStatus(rawValue: statusValue) == .complete else { return nil }

        let bufferSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let scaleFactor = info[.scaleFactor] as? CGFloat ?? 1
        let contentScale = info[.contentScale] as? CGFloat ?? 1
        let contentRect = (info[.contentRect] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
            ?? CGRect(x: 0, y: 0, width: bufferSize.width / scaleFactor, height: bufferSize.height / scaleFactor)

        return ScreenFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: sampleBuffer.presentationTimeStamp,
            contentRect: contentRect,
            scaleFactor: scaleFactor,
            contentScale: contentScale
        )
    }
}
