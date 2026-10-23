// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import AVFoundation
import CoreGraphics

/// The single gateway to TCC. Nothing here runs at launch; every `request` is the consequence of a user action.
final class PermissionsService: PermissionsChecking {
    private let flags: PermissionFlagsStore

    init(flags: PermissionFlagsStore) {
        self.flags = flags
    }

    func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                return .authorized
            }
            return flags.hasRequested(.screenRecording) ? .denied : .notDetermined
        case .camera:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        }
    }

    func request(_ permission: Permission) async -> PermissionStatus {
        Log.permissions.info("Requesting \(permission.rawValue, privacy: .public) after a user action")
        switch permission {
        case .screenRecording:
            flags.markRequested(.screenRecording)
            // Shows the system prompt once; later calls return the stored decision.
            let granted = await MainActor.run { CGRequestScreenCaptureAccess() }
            return granted || CGPreflightScreenCaptureAccess() ? .authorized : .denied
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return status(of: .camera)
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            return status(of: .microphone)
        }
    }

    @MainActor
    func openSystemSettings(for permission: Permission) {
        let pane = switch permission {
        case .screenRecording: "Privacy_ScreenCapture"
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Starts a second instance and quits this one only once the new one is confirmed running, so the
    /// user ends up with exactly one LibreScreen (macOS applies Screen Recording on the next launch).
    @MainActor
    func relaunchApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            Task { @MainActor in
                guard application != nil, error == nil else {
                    Log.permissions.error("Relaunch failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                    return
                }
                NSApp.terminate(nil)
                // `terminate` can be refused (for example by a sheet); never leave two instances behind.
                try? await Task.sleep(for: .milliseconds(500))
                exit(0)
            }
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}
