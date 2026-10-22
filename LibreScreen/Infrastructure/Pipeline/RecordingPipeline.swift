// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreMedia
import CoreVideo
import Foundation

/// The real-time path: screen frames and audio come in on capture queues, a fixed-rate clock composites
/// the latest frames and hands them to the writer. All mutable state lives on `queue`; the unchecked
/// `Sendable` conformance is justified by that single-queue ownership.
/// Counters for diagnostics and the debug automation; read through `statistics()`.
struct PipelineStatistics: Sendable {
    var screenFrames = 0
    var systemAudioBuffers = 0
    var microphoneBuffers = 0
    var ticks = 0
    var appendedFrames = 0
    var droppedFrames = 0
    var lastStreamError: String?

    var summary: String {
        "screenFrames=\(screenFrames) systemAudio=\(systemAudioBuffers) mic=\(microphoneBuffers) ticks=\(ticks)"
            + " appended=\(appendedFrames) dropped=\(droppedFrames) streamError=\(lastStreamError ?? "none")"
    }
}

final class RecordingPipeline: RecordingCoordinating, @unchecked Sendable {
    private enum State {
        case idle
        case recording
        case paused
        case finishing
    }

    /// What `teardown` hands back so the caller can finish or discard the file off the queue.
    private struct Session {
        let writer: RecordingWriter
        let engine: ScreenCaptureEngine
        let microphone: MicrophoneCaptureService?
        let elapsed: TimeInterval
        let startedAt: Date
        let pixelSize: CGSize
    }

    private let queue = DispatchQueue(label: "br.com.asoft.LibreScreen.pipeline", qos: .userInteractive)
    private let compositor = FrameCompositor()
    private let cameraSource: (any CameraFrameSource)?

    private var state: State = .idle
    private var request: RecordingRequest?
    private var engine: ScreenCaptureEngine?
    private var microphone: MicrophoneCaptureService?
    private var writer: RecordingWriter?
    private var clock: FrameClock?
    private var outputSize: CGSize = .zero

    private var latestScreenFrame: ScreenFrame?
    private var lastComposedScreenTime = CMTime.invalid
    private var lastComposedCameraTime = CMTime.invalid
    private var startTime = CMTime.zero
    private var startedAt = Date()
    private var pauseStartedAt: CMTime?
    private var pausedOffset = CMTime.zero
    private var continuations: [UUID: AsyncStream<RecordingEvent>.Continuation] = [:]
    private var statistics = PipelineStatistics()

    init(cameraSource: (any CameraFrameSource)?) {
        self.cameraSource = cameraSource
    }

    // MARK: - RecordingCoordinating

    func start(_ request: RecordingRequest) async throws {
        try await ensureIdle()
        let pixelSize = request.source.pixelSize(for: request.settings.resolution)
        let writer = try Self.makeWriter(for: request, pixelSize: pixelSize)
        let microphone = try await startMicrophone(for: request, writer: writer)
        let engine = ScreenCaptureEngine()
        do {
            try await engine.start(
                source: request.source,
                configuration: Self.captureConfiguration(for: request, pixelSize: pixelSize),
                sink: self
            )
        } catch {
            await microphone?.stop()
            writer.cancel()
            throw error
        }
        await activate(request: request, writer: writer, engine: engine, microphone: microphone, pixelSize: pixelSize)
    }

    func pause() async {
        await onQueue { [self] in
            guard state == .recording else { return }
            state = .paused
            pauseStartedAt = CMClockGetTime(CMClockGetHostTimeClock())
            emit(.paused)
        }
    }

    func resume() async {
        await onQueue { [self] in
            guard state == .paused, let pauseStartedAt else { return }
            pausedOffset = CMTimeAdd(pausedOffset, CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), pauseStartedAt))
            self.pauseStartedAt = nil
            state = .recording
            emit(.resumed)
        }
    }

    func stop() async throws -> RecordingResult {
        guard let session = await teardown() else {
            throw LibreScreenError.captureFailed(reason: "no active recording")
        }
        let url = try await session.writer.finish()
        Log.pipeline.notice("Recording stopped after \(session.elapsed, format: .fixed(precision: 1))s")
        return RecordingResult(url: url, duration: session.elapsed, pixelSize: session.pixelSize, startedAt: session.startedAt)
    }

    func cancel() async {
        guard let session = await teardown() else { return }
        session.writer.cancel()
    }

    func elapsedTime() async -> TimeInterval {
        await withCheckedContinuation { (continuation: CheckedContinuation<TimeInterval, Never>) in
            queue.async { [weak self] in
                continuation.resume(returning: self?.currentElapsed() ?? 0)
            }
        }
    }

    func statistics() async -> PipelineStatistics {
        await withCheckedContinuation { (continuation: CheckedContinuation<PipelineStatistics, Never>) in
            queue.async { [weak self] in
                continuation.resume(returning: self?.statistics ?? PipelineStatistics())
            }
        }
    }

    func events() -> AsyncStream<RecordingEvent> {
        AsyncStream { continuation in
            let id = UUID()
            queue.async { [weak self] in
                self?.continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    // MARK: - Start helpers

    private static func makeWriter(for request: RecordingRequest, pixelSize: CGSize) throws -> RecordingWriter {
        var tracks: Set<AudioTrack> = []
        if request.settings.capturesSystemAudio {
            tracks.insert(.system)
        }
        if request.settings.microphoneEnabled {
            tracks.insert(.microphone)
        }
        let configuration = WriterConfiguration(
            outputURL: request.outputURL,
            container: request.settings.container,
            codec: request.settings.codec,
            pixelSize: pixelSize,
            frameRate: request.settings.frameRate.rawValue,
            bitrate: request.settings.bitrate(for: pixelSize),
            audioTracks: tracks
        )
        let writer = try RecordingWriter(configuration: configuration)
        try writer.start()
        return writer
    }

    private static func captureConfiguration(for request: RecordingRequest, pixelSize: CGSize) -> ScreenCaptureConfiguration {
        let sourceRect: CGRect? = if case let .region(region) = request.source {
            region.rect
        } else {
            nil
        }
        return ScreenCaptureConfiguration(
            pixelSize: pixelSize,
            frameRate: request.settings.frameRate.rawValue,
            showsCursor: request.settings.showsCursor,
            capturesAudio: request.settings.capturesSystemAudio,
            sourceRect: sourceRect
        )
    }

    private func startMicrophone(for request: RecordingRequest, writer: RecordingWriter) async throws -> MicrophoneCaptureService? {
        guard request.settings.microphoneEnabled else { return nil }
        let microphone = MicrophoneCaptureService()
        do {
            try await microphone.start(deviceID: request.settings.microphoneDeviceID, sink: self) { [weak self] level in
                self?.queue.async { [weak self] in self?.emit(.microphoneLevel(level)) }
            }
        } catch {
            writer.cancel()
            throw error
        }
        return microphone
    }

    private func activate(
        request: RecordingRequest,
        writer: RecordingWriter,
        engine: ScreenCaptureEngine,
        microphone: MicrophoneCaptureService?,
        pixelSize: CGSize
    ) async {
        await onQueue { [self] in
            self.request = request
            self.writer = writer
            self.engine = engine
            self.microphone = microphone
            outputSize = pixelSize
            latestScreenFrame = nil
            lastComposedScreenTime = .invalid
            lastComposedCameraTime = .invalid
            pausedOffset = .zero
            pauseStartedAt = nil
            startTime = CMClockGetTime(CMClockGetHostTimeClock())
            startedAt = Date()
            statistics = PipelineStatistics()
            state = .recording
            let clock = FrameClock(frameRate: request.settings.frameRate.rawValue, queue: queue) { [weak self] in
                self?.tick()
            }
            self.clock = clock
            clock.start()
            emit(.started)
        }
    }

    // MARK: - Queue-confined work

    /// Constant frame rate: every tick composites into a fresh pool buffer and appends it. Re-appending
    /// the previous buffer while the encoder still references it made AVFoundation copy it internally
    /// and memory grew without bound, so each frame gets its own buffer even when nothing changed.
    private func tick() {
        guard state == .recording, let writer, let screen = latestScreenFrame else { return }
        let overlay = request?.overlay
        let camera = overlay?.enabled == true ? cameraSource?.latestFrame : nil
        let time = CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), pausedOffset)
        statistics.ticks += 1

        guard let pool = writer.pixelBufferPool else { return }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else { return }
        autoreleasepool {
            compositor.compose(screen: screen, camera: camera, overlay: overlay, outputSize: outputSize, into: pixelBuffer)
        }
        count(writer.append(pixelBuffer, at: time), at: time)
        lastComposedScreenTime = screen.presentationTime
        if let camera {
            lastComposedCameraTime = camera.presentationTime
        }
    }

    private func count(_ appended: Bool, at time: CMTime) {
        if appended {
            if statistics.appendedFrames == 0 {
                // Elapsed time and the file both start at the first frame, not at activation.
                startTime = time
            }
            statistics.appendedFrames += 1
        } else {
            statistics.droppedFrames += 1
        }
    }

    private func currentElapsed() -> TimeInterval {
        guard state != .idle, statistics.appendedFrames > 0 else { return 0 }
        let now = pauseStartedAt ?? CMClockGetTime(CMClockGetHostTimeClock())
        return max(CMTimeSubtract(CMTimeSubtract(now, pausedOffset), startTime).seconds, 0)
    }

    private func emit(_ event: RecordingEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func ensureIdle() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [weak self] in
                guard let self else { return continuation.resume() }
                if state == .idle {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: LibreScreenError.alreadyRecording)
                }
            }
        }
    }

    private func onQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }

    /// Stops the clock and capture sources; returns `nil` when nothing was recording.
    private func teardown() async -> Session? {
        let session: Session? = await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self, state == .recording || state == .paused, let writer, let engine else {
                    return continuation.resume(returning: nil)
                }
                state = .finishing
                clock?.stop()
                clock = nil
                let session = Session(
                    writer: writer,
                    engine: engine,
                    microphone: microphone,
                    elapsed: currentElapsed(),
                    startedAt: startedAt,
                    pixelSize: outputSize
                )
                self.writer = nil
                self.engine = nil
                microphone = nil
                request = nil
                latestScreenFrame = nil
                continuation.resume(returning: session)
            }
        }
        guard let session else { return nil }
        await session.engine.stop()
        await session.microphone?.stop()
        await onQueue { [self] in
            state = .idle
        }
        return session
    }
}

// MARK: - Sinks (called on capture queues)

extension RecordingPipeline: ScreenFrameSink, MicrophoneSampleSink {
    func screenCapture(didOutput frame: ScreenFrame) {
        queue.async { [weak self] in
            guard let self, state == .recording || state == .paused else { return }
            // Replacing the slot releases the previous buffer so ScreenCaptureKit never starves.
            latestScreenFrame = frame
            statistics.screenFrames += 1
        }
    }

    func screenCapture(didOutputAudio sampleBuffer: CMSampleBuffer) {
        let box = SampleBufferBox(buffer: sampleBuffer)
        queue.async { [weak self] in
            guard let self, state == .recording, let shifted = box.buffer.shifted(byNegative: pausedOffset) else { return }
            statistics.systemAudioBuffers += 1
            writer?.append(shifted, to: .system)
        }
    }

    func screenCapture(didStopWith error: any Error) {
        queue.async { [weak self] in
            guard let self, state == .recording || state == .paused else { return }
            statistics.lastStreamError = error.localizedDescription
            emit(.failed(.captureFailed(reason: error.localizedDescription)))
        }
    }

    func microphone(didOutput sampleBuffer: CMSampleBuffer) {
        let box = SampleBufferBox(buffer: sampleBuffer)
        queue.async { [weak self] in
            guard let self, state == .recording, let shifted = box.buffer.shifted(byNegative: pausedOffset) else { return }
            statistics.microphoneBuffers += 1
            writer?.append(shifted, to: .microphone)
        }
    }
}
