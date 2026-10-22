// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Fixed-rate tick on a given queue. Drives output so the camera bubble keeps animating even when
/// the screen is static (ScreenCaptureKit only delivers frames when pixels change).
final class FrameClock: @unchecked Sendable {
    private let timer: DispatchSourceTimer
    private var isResumed = false

    init(frameRate: Int, queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = DispatchTimeInterval.nanoseconds(1_000_000_000 / max(frameRate, 1))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler(handler: handler)
    }

    deinit {
        // A suspended source must be resumed before it can be released.
        if !isResumed {
            timer.resume()
        }
        timer.cancel()
    }

    func start() {
        guard !isResumed else { return }
        isResumed = true
        timer.resume()
    }

    func stop() {
        timer.cancel()
    }
}
