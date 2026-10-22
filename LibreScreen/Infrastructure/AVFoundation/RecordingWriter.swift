// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AVFoundation
import CoreVideo

enum AudioTrack: Hashable, Sendable {
    case microphone
    case system
}

struct WriterConfiguration: Sendable {
    let outputURL: URL
    let container: VideoContainer
    let codec: VideoCodec
    let pixelSize: CGSize
    let frameRate: Int
    let bitrate: Int
    let audioTracks: Set<AudioTrack>
}

/// `AVAssetWriter` with one composited video track and up to two AAC tracks. Not thread-safe:
/// every method must be called from the pipeline queue, which is what the unchecked `Sendable` relies on.
final class RecordingWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audioInputs: [AudioTrack: AVAssetWriterInput] = [:]
    private var sessionStartTime: CMTime?
    private var lastVideoTime = CMTime.invalid
    private(set) var appendedFrames = 0
    private(set) var droppedFrames = 0

    let configuration: WriterConfiguration

    init(configuration: WriterConfiguration) throws {
        self.configuration = configuration
        do {
            writer = try AVAssetWriter(outputURL: configuration.outputURL, fileType: configuration.container == .mp4 ? .mp4 : .mov)
        } catch {
            throw LibreScreenError.writerFailed(reason: error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(configuration))
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(configuration.pixelSize.width),
                kCVPixelBufferHeightKey as String: Int(configuration.pixelSize.height),
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(videoInput) else { throw LibreScreenError.writerFailed(reason: "video input") }
        writer.add(videoInput)

        for track in configuration.audioTracks {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw LibreScreenError.writerFailed(reason: "audio input") }
            writer.add(input)
            audioInputs[track] = input
        }
    }

    /// The adaptor's pool, available once writing has started. Compositing renders straight into it.
    var pixelBufferPool: CVPixelBufferPool? {
        adaptor.pixelBufferPool
    }

    func start() throws {
        guard writer.startWriting() else {
            throw LibreScreenError.writerFailed(reason: writer.error?.localizedDescription ?? "startWriting")
        }
    }

    /// Appends a composited frame. The first frame opens the session; audio before it is dropped to keep sync.
    @discardableResult
    func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        if sessionStartTime == nil {
            writer.startSession(atSourceTime: time)
            sessionStartTime = time
        }
        // `lastVideoTime` starts invalid; comparing against an invalid CMTime is never true.
        let isMonotonic = !lastVideoTime.isValid || time > lastVideoTime
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData, isMonotonic else {
            droppedFrames += 1
            return false
        }
        guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
            droppedFrames += 1
            Log.writer.error("Video append failed: \(self.writer.error?.localizedDescription ?? "unknown", privacy: .public)")
            return false
        }
        lastVideoTime = time
        appendedFrames += 1
        return true
    }

    func append(_ sampleBuffer: CMSampleBuffer, to track: AudioTrack) {
        guard
            let start = sessionStartTime,
            sampleBuffer.presentationTimeStamp >= start,
            writer.status == .writing,
            let input = audioInputs[track],
            input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func finish() async throws -> URL {
        videoInput.markAsFinished()
        audioInputs.values.forEach { $0.markAsFinished() }
        guard sessionStartTime != nil else {
            writer.cancelWriting()
            throw LibreScreenError.writerFailed(reason: String(localized: "nenhum quadro foi capturado"))
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw LibreScreenError.writerFailed(reason: writer.error?.localizedDescription ?? "finishWriting")
        }
        Log.writer.notice("Finished: \(self.appendedFrames) frames, \(self.droppedFrames) dropped")
        return configuration.outputURL
    }

    func cancel() {
        if writer.status == .writing {
            writer.cancelWriting()
        }
        try? FileManager.default.removeItem(at: configuration.outputURL)
    }

    private static func videoSettings(_ configuration: WriterConfiguration) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: configuration.bitrate,
            AVVideoExpectedSourceFrameRateKey: configuration.frameRate,
            AVVideoMaxKeyFrameIntervalKey: configuration.frameRate * 2,
            AVVideoAllowFrameReorderingKey: false
        ]
        let codec: AVVideoCodecType
        switch configuration.codec {
        case .h264:
            codec = .h264
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        case .hevc:
            codec = .hevc
        }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(configuration.pixelSize.width),
            AVVideoHeightKey: Int(configuration.pixelSize.height),
            AVVideoCompressionPropertiesKey: compression
        ]
    }

    private static var audioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
    }
}
