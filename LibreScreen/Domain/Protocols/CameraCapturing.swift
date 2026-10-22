// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Per-frame processing applied to the webcam before preview and compositing.
struct CameraProcessingOptions: Sendable, Equatable {
    var blurEnabled: Bool
    var blurIntensity: Double
    var mirrored: Bool

    init(blurEnabled: Bool, blurIntensity: Double, mirrored: Bool) {
        self.blurEnabled = blurEnabled
        self.blurIntensity = blurIntensity
        self.mirrored = mirrored
    }

    init(settings: CameraOverlaySettings) {
        self.init(blurEnabled: settings.blurEnabled, blurIntensity: settings.blurIntensity, mirrored: settings.mirrored)
    }
}

/// Controls the webcam session. Starting requires the Camera permission to be authorized already.
protocol CameraCapturing: AnyObject, Sendable {
    func start(deviceID: String?, options: CameraProcessingOptions) async throws
    func stop() async
    func updateProcessing(_ options: CameraProcessingOptions) async
    var isRunning: Bool { get async }
}
