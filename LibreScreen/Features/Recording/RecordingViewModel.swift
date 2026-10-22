// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import Foundation
import Observation

/// Floating UI the recording flow needs, implemented by `WindowCoordinator`.
@MainActor
protocol RecordingPresenting: AnyObject {
    func showCountdown(_ seconds: Int, on display: DisplayInfo?)
    func hideCountdown()
    func showRecordingHUD(for source: CaptureSource)
    func hideRecordingHUD()
    func showCaptureResult(_ item: CaptureItem)
    func recordingDidStart()
}

/// Owns the recording state machine: idle → preparing → countdown → recording ⇄ paused → finishing.
@MainActor
@Observable
final class RecordingViewModel {
    private(set) var phase: RecordingPhase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var microphoneLevel: Float = 0
    private(set) var currentSource: CaptureSource?

    weak var presenter: (any RecordingPresenting)?
    /// Receives every failure so the hub can show it; set by the composition root.
    var errorHandler: (@MainActor (any Error) -> Void)?
    /// Fired after a new item is stored so lists can refresh.
    var didStoreItem: (@MainActor (CaptureItem) -> Void)?

    private let useCase: StartRecordingUseCase
    private let recorder: any RecordingCoordinating
    private let captures: any CaptureStoring
    private let settings: SettingsStore
    private var countdownCancelled = false
    private var ticker: Task<Void, Never>?
    private var eventObserver: Task<Void, Never>?

    init(useCase: StartRecordingUseCase, recorder: any RecordingCoordinating, captures: any CaptureStoring, settings: SettingsStore) {
        self.useCase = useCase
        self.recorder = recorder
        self.captures = captures
        self.settings = settings
    }

    var isRecordingOrPaused: Bool {
        phase == .recording || phase == .paused
    }

    // MARK: - Lifecycle

    func start(source: CaptureSource) async {
        guard phase == .idle else { return }
        phase = .preparing
        currentSource = source
        let recordingSettings = settings.settings.recording
        let overlay = settings.settings.camera
        do {
            let request = try await useCase.prepare(source: source, settings: recordingSettings, overlay: overlay)
            guard await runCountdown(seconds: recordingSettings.countdownSeconds, display: source.displayInfo) else {
                phase = .idle
                return
            }
            try await useCase.start(request)
            elapsed = 0
            phase = .recording
            presenter?.showRecordingHUD(for: source)
            presenter?.recordingDidStart()
            startTicker()
            observeEvents()
        } catch {
            presenter?.hideCountdown()
            phase = .idle
            report(error)
        }
    }

    func cancelCountdown() {
        countdownCancelled = true
    }

    func pause() async {
        guard phase == .recording else { return }
        await recorder.pause()
        phase = .paused
    }

    func resume() async {
        guard phase == .paused else { return }
        await recorder.resume()
        phase = .recording
    }

    func togglePause() async {
        if phase == .paused {
            await resume()
        } else {
            await pause()
        }
    }

    func stop() async {
        if case .countdown = phase {
            cancelCountdown()
            return
        }
        guard phase.canStop else { return }
        phase = .finishing
        stopObserving()
        presenter?.hideRecordingHUD()
        do {
            let result = try await recorder.stop()
            let item = CaptureItem(
                kind: .recording,
                url: result.url,
                createdAt: result.startedAt,
                duration: result.duration,
                pixelSize: result.pixelSize,
                sourceSummary: currentSource?.summary ?? ""
            )
            await captures.add(item)
            phase = .idle
            didStoreItem?(item)
            if settings.settings.general.showsThumbnailPanel {
                presenter?.showCaptureResult(item)
            }
            if settings.settings.general.revealsInFinderAfterRecording {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        } catch {
            phase = .idle
            report(error)
        }
    }

    func cancel() async {
        guard phase.isActive else { return }
        if case .countdown = phase {
            cancelCountdown()
            return
        }
        stopObserving()
        presenter?.hideRecordingHUD()
        await recorder.cancel()
        phase = .idle
    }

    // MARK: - Internals

    private func runCountdown(seconds: Int, display: DisplayInfo?) async -> Bool {
        guard seconds > 0 else { return true }
        countdownCancelled = false
        for remaining in stride(from: seconds, through: 1, by: -1) {
            phase = .countdown(remaining)
            presenter?.showCountdown(remaining, on: display)
            try? await Task.sleep(for: .seconds(1))
            if countdownCancelled {
                presenter?.hideCountdown()
                return false
            }
        }
        presenter?.hideCountdown()
        return true
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                elapsed = await recorder.elapsedTime()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func observeEvents() {
        eventObserver?.cancel()
        eventObserver = Task { [weak self] in
            guard let stream = self?.recorder.events() else { return }
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case let .microphoneLevel(level):
                    microphoneLevel = level
                case let .failed(error):
                    await handleFailure(error)
                case .started, .paused, .resumed:
                    break
                }
            }
        }
    }

    private func stopObserving() {
        ticker?.cancel()
        ticker = nil
        eventObserver?.cancel()
        eventObserver = nil
    }

    private func handleFailure(_ error: LibreScreenError) async {
        stopObserving()
        presenter?.hideRecordingHUD()
        await recorder.cancel()
        phase = .idle
        report(error)
    }

    private func report(_ error: any Error) {
        Log.pipeline.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        errorHandler?(error)
    }
}
