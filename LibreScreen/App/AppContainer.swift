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

    let hub: HubViewModel
    let permissionsViewModel: PermissionsViewModel

    @ObservationIgnored
    private(set) lazy var windows = WindowCoordinator(container: self)

    init(
        settings: SettingsStore,
        permissions: any PermissionsChecking,
        devices: any MediaDeviceProviding,
        content: any ShareableContentProviding,
        captures: any CaptureStoring,
        output: any OutputLocating
    ) {
        self.settings = settings
        self.permissions = permissions
        self.devices = devices
        self.content = content
        self.captures = captures
        self.output = output

        hub = HubViewModel(settings: settings, content: content, devices: devices, permissions: permissions)
        permissionsViewModel = PermissionsViewModel(permissions: permissions)
    }

    /// The production wiring.
    static func live() -> AppContainer {
        let defaults = UserDefaults.standard
        let settings = SettingsStore(defaults: defaults)
        let permissions = PermissionsService(flags: PermissionFlagsStore(defaults: defaults))
        return AppContainer(
            settings: settings,
            permissions: permissions,
            devices: MediaDeviceService(),
            content: ShareableContentService(permissions: permissions),
            captures: CaptureStore(),
            output: OutputDirectories()
        )
    }
}
