// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// Composition root. Builds every service once, wires them into protocols and owns the app-lifetime
/// view models. Views reach it through `@Environment(AppContainer.self)`.
@MainActor
@Observable
final class AppContainer {
    let settings: SettingsStore
    let permissions: any PermissionsChecking
    let devices: any MediaDeviceProviding
    let content: any ShareableContentProviding
    let captures: any CaptureStoring
    let output: any OutputLocating
    let recorder: any RecordingCoordinating
    let thumbnails: ThumbnailLoader
    let camera: any CameraService
    let screenshots: any Screenshotting
    let encoder: any ImageEncoding

    let recording: RecordingViewModel
    let screenshot: ScreenshotViewModel
    let hub: HubViewModel
    let permissionsViewModel: PermissionsViewModel
    let cameraCoordinator: CameraSessionCoordinator
    let hotkeys: HotkeyCoordinator

    @ObservationIgnored
    private(set) lazy var windows = WindowCoordinator(container: self)

    init(
        settings: SettingsStore,
        permissions: any PermissionsChecking,
        devices: any MediaDeviceProviding,
        content: any ShareableContentProviding,
        captures: any CaptureStoring,
        output: any OutputLocating,
        recorder: any RecordingCoordinating,
        thumbnails: ThumbnailLoader,
        camera: any CameraService,
        screenshots: any Screenshotting,
        encoder: any ImageEncoding,
        hotkeyRegistrar: any HotkeyRegistering
    ) {
        self.settings = settings
        self.permissions = permissions
        self.devices = devices
        self.content = content
        self.captures = captures
        self.output = output
        self.recorder = recorder
        self.thumbnails = thumbnails
        self.camera = camera
        self.screenshots = screenshots
        self.encoder = encoder

        let startRecording = StartRecordingUseCase(permissions: permissions, recorder: recorder, output: output)
        recording = RecordingViewModel(useCase: startRecording, recorder: recorder, captures: captures, settings: settings)
        let takeScreenshot = TakeScreenshotUseCase(
            permissions: permissions,
            screenshots: screenshots,
            encoder: encoder,
            output: output,
            store: captures
        )
        screenshot = ScreenshotViewModel(useCase: takeScreenshot, settings: settings)
        hub = HubViewModel(
            settings: settings,
            content: content,
            devices: devices,
            permissions: permissions,
            captures: captures,
            recording: recording,
            screenshot: screenshot,
            thumbnails: thumbnails
        )
        permissionsViewModel = PermissionsViewModel(permissions: permissions)
        hotkeys = HotkeyCoordinator(registrar: hotkeyRegistrar, settings: settings)
        cameraCoordinator = CameraSessionCoordinator(
            camera: camera,
            settings: settings,
            permissions: permissions,
            hub: hub,
            recording: recording
        )

        recording.errorHandler = { [weak self] error in self?.hub.present(error) }
        recording.didStoreItem = { [weak self] _ in
            Task { await self?.hub.refreshRecents() }
        }
        screenshot.errorHandler = { [weak self] error in self?.hub.present(error) }
        screenshot.didStoreItem = { [weak self] _ in
            Task { await self?.hub.refreshRecents() }
        }
    }

    /// The production wiring.
    static func live() -> AppContainer {
        let defaults = UserDefaults.standard
        let settings = SettingsStore(defaults: defaults)
        let permissions = PermissionsService(flags: PermissionFlagsStore(defaults: defaults))
        let camera = CameraCaptureService()
        return AppContainer(
            settings: settings,
            permissions: permissions,
            devices: MediaDeviceService(),
            content: ShareableContentService(permissions: permissions),
            captures: CaptureStore(),
            output: OutputDirectories(),
            recorder: RecordingPipeline(cameraSource: camera),
            thumbnails: ThumbnailLoader(),
            camera: camera,
            screenshots: ScreenshotService(),
            encoder: ImageFileWriter(),
            hotkeyRegistrar: CarbonHotkeyService()
        )
    }
}
