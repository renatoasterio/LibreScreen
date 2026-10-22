// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Permission gating and output naming for a new recording. Split in two steps so the view model can
/// run the countdown between them without holding capture resources.
struct StartRecordingUseCase: Sendable {
    let permissions: any PermissionsChecking
    let recorder: any RecordingCoordinating
    let output: any OutputLocating

    /// Requests whatever permissions the chosen options need (this is a user action) and resolves the file URL.
    func prepare(
        source: CaptureSource,
        settings: RecordingSettings,
        overlay: CameraOverlaySettings,
        date: Date = Date()
    ) async throws -> RecordingRequest {
        try await ensureAuthorized(.screenRecording)
        if overlay.enabled {
            try await ensureAuthorized(.camera)
        }
        if settings.microphoneEnabled {
            try await ensureAuthorized(.microphone)
        }
        let url = try output.recordingURL(
            container: settings.container,
            source: source,
            directory: settings.outputDirectory,
            date: date
        )
        return RecordingRequest(source: source, settings: settings, overlay: overlay, outputURL: url)
    }

    func start(_ request: RecordingRequest) async throws {
        try await recorder.start(request)
    }

    private func ensureAuthorized(_ permission: Permission) async throws {
        var status = permissions.status(of: permission)
        if status == .notDetermined {
            status = await permissions.request(permission)
        }
        guard status.isAuthorized else {
            throw LibreScreenError.permissionDenied(permission)
        }
    }
}
