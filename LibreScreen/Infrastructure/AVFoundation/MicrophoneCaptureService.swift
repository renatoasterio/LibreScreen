// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AVFoundation

/// Microphone capture through its own `AVCaptureSession`. Buffers reach the sink on the capture queue,
/// which is also the only queue that mutates session state (hence the unchecked `Sendable`).
final class MicrophoneCaptureService: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "br.com.asoft.LibreScreen.microphone", qos: .userInteractive)
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private var input: AVCaptureDeviceInput?
    private weak var sink: (any MicrophoneSampleSink)?
    private var levelHandler: (@Sendable (Float) -> Void)?
    private var buffersSinceLevel = 0

    func start(deviceID: String?, sink: any MicrophoneSampleSink, levelHandler: (@Sendable (Float) -> Void)? = nil) async throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw LibreScreenError.permissionDenied(.microphone)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // lifetime: the continuation keeps this block alive only until the session is configured.
            queue.async { [self] in
                do {
                    // Resolved here because AVCaptureDevice is not Sendable.
                    let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
                    guard let device else { throw LibreScreenError.microphoneUnavailable }
                    let deviceInput = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    guard session.canAddInput(deviceInput), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw LibreScreenError.microphoneUnavailable
                    }
                    session.addInput(deviceInput)
                    session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: queue)
                    session.commitConfiguration()
                    input = deviceInput
                    self.sink = sink
                    self.levelHandler = levelHandler
                    session.startRunning()
                    Log.audio.info("Microphone started: \(device.localizedName, privacy: .private)")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: LibreScreenError.microphoneUnavailable)
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
                sink = nil
                levelHandler = nil
                continuation.resume()
            }
        }
    }
}

extension MicrophoneCaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        sink?.microphone(didOutput: sampleBuffer)
        guard let levelHandler else { return }
        buffersSinceLevel += 1
        guard buffersSinceLevel >= 4 else { return }
        buffersSinceLevel = 0
        let decibels = connection.audioChannels.map(\.averagePowerLevel).max() ?? -160
        levelHandler(min(max((decibels + 50) / 50, 0), 1))
    }
}
