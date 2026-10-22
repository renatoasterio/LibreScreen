// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import Foundation
import Observation

typealias CameraService = CameraCapturing & CameraFrameSource

/// Keeps the webcam session and the preview bubble in sync with the camera settings, the Camera
/// permission and the capture target. The camera only runs while the user has it enabled in Record
/// mode, and the permission is requested the moment the user turns it on, never before.
@MainActor
final class CameraSessionCoordinator {
    private struct Appearance: Equatable {
        let shape: OverlayShape
        let size: OverlaySize
        let border: Bool
        let shadow: Bool

        init(_ settings: CameraOverlaySettings) {
            shape = settings.shape
            size = settings.size
            border = settings.showsBorder
            shadow = settings.showsShadow
        }
    }

    private let camera: any CameraService
    private let settings: SettingsStore
    private let permissions: any PermissionsChecking
    private unowned let hub: HubViewModel
    private unowned let recording: RecordingViewModel
    private let bubble = CameraBubbleController()

    private var appliedDeviceID: String?
    private var appliedOptions: CameraProcessingOptions?
    private var appliedAppearance: Appearance?
    private var pending: Task<Void, Never>?
    private var isActive = false

    init(
        camera: any CameraService,
        settings: SettingsStore,
        permissions: any PermissionsChecking,
        hub: HubViewModel,
        recording: RecordingViewModel
    ) {
        self.camera = camera
        self.settings = settings
        self.permissions = permissions
        self.hub = hub
        self.recording = recording
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        bubble.onCornerChange = { [weak self] corner in
            self?.settings.settings.camera.corner = corner
        }
        observe()
        apply()
    }

    /// Re-registers observation after every change (the `withObservationTracking` callback fires once).
    private func observe() {
        withObservationTracking {
            _ = settings.settings.camera
            _ = hub.selectedSource
            _ = hub.mode
            _ = recording.currentSource
            _ = recording.phase
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observe()
                self?.apply()
            }
        }
    }

    private func apply() {
        let cameraSettings = settings.settings.camera
        let wanted = cameraSettings.enabled && hub.mode == .record
        // Serialise start/stop so a quick toggle never interleaves two reconciliations.
        pending = Task { [weak self, previous = pending] in
            await previous?.value
            await self?.reconcile(wanted: wanted, cameraSettings: cameraSettings)
        }
    }

    private func reconcile(wanted: Bool, cameraSettings: CameraOverlaySettings) async {
        guard wanted else {
            await stopIfNeeded()
            return
        }
        guard await ensureAuthorized() else { return }
        let options = CameraProcessingOptions(settings: cameraSettings)
        if await !camera.isRunning || appliedDeviceID != cameraSettings.deviceID {
            do {
                try await camera.start(deviceID: cameraSettings.deviceID, options: options)
                appliedDeviceID = cameraSettings.deviceID
                appliedOptions = options
            } catch {
                settings.settings.camera.enabled = false
                hub.present(error)
                return
            }
        } else if appliedOptions != options {
            await camera.updateProcessing(options)
            appliedOptions = options
        }
        showBubble(cameraSettings)
    }

    private func ensureAuthorized() async -> Bool {
        var status = permissions.status(of: .camera)
        if status == .notDetermined {
            status = await permissions.request(.camera)
        }
        guard status.isAuthorized else {
            settings.settings.camera.enabled = false
            hub.present(LibreScreenError.permissionDenied(.camera))
            return false
        }
        return true
    }

    private func stopIfNeeded() async {
        bubble.hide()
        appliedAppearance = nil
        if await camera.isRunning {
            await camera.stop()
        }
        appliedDeviceID = nil
        appliedOptions = nil
    }

    private func showBubble(_ cameraSettings: CameraOverlaySettings) {
        let target = targetRect()
        let appearance = Appearance(cameraSettings)
        if bubble.isVisible, appliedAppearance == appearance {
            bubble.update(settings: cameraSettings, targetRect: target)
        } else {
            bubble.show(source: camera, settings: cameraSettings, targetRect: target)
            appliedAppearance = appearance
        }
    }

    /// The on-screen rectangle (AppKit coordinates) the bubble is positioned against.
    private func targetRect() -> CGRect {
        let source = recording.currentSource ?? hub.selectedSource
        let fallback = NSScreen.main?.visibleFrame ?? .zero
        guard let source else { return fallback }
        let global: CGRect = switch source {
        case let .display(display): display.frame
        case let .window(window): window.frame
        case let .region(region): region.globalRect
        }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CaptureCoordinates.appKitRect(fromGlobal: global, mainDisplayHeight: mainHeight)
    }
}
