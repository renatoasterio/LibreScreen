// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Per-frame processing applied to the webcam before preview and compositing.
struct CameraProcessingOptions: Sendable, Equatable {
    var background: CameraBackgroundMode
    var backgroundImageURL: URL?
    var blurIntensity: Double
    var mirrored: Bool

    init(background: CameraBackgroundMode, backgroundImageURL: URL? = nil, blurIntensity: Double, mirrored: Bool) {
        self.background = background
        self.backgroundImageURL = backgroundImageURL
        self.blurIntensity = blurIntensity
        self.mirrored = mirrored
    }

    init(settings: CameraOverlaySettings) {
        self.init(
            background: settings.background,
            backgroundImageURL: settings.backgroundImageURL,
            blurIntensity: settings.blurIntensity,
            mirrored: settings.mirrored
        )
    }
}

/// Controls the webcam session. Starting requires the Camera permission to be authorized already.
protocol CameraCapturing: AnyObject, Sendable {
    func start(deviceID: String?, options: CameraProcessingOptions) async throws
    func stop() async
    func updateProcessing(_ options: CameraProcessingOptions) async
    var isRunning: Bool { get async }
}
