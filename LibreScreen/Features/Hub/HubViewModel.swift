// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// State behind the main window: what to capture, with which devices, and the primary action.
@MainActor
@Observable
final class HubViewModel {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case record
        case screenshot

        var id: String {
            rawValue
        }
    }

    struct AlertContent: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        let permission: Permission?
    }

    var mode: Mode = .record
    var sourceKind: SourceKind = .display
    var selectedDisplayID: UInt32?
    var selectedWindow: WindowInfo?
    var selectedRegion: RegionInfo?
    var alert: AlertContent?
    var isPresentingPermissions = false

    private(set) var displays: [DisplayInfo] = []
    private(set) var cameras: [MediaDevice] = []
    private(set) var microphones: [MediaDevice] = []

    let settings: SettingsStore
    private let content: any ShareableContentProviding
    private let devices: any MediaDeviceProviding
    private let permissions: any PermissionsChecking

    init(
        settings: SettingsStore,
        content: any ShareableContentProviding,
        devices: any MediaDeviceProviding,
        permissions: any PermissionsChecking
    ) {
        self.settings = settings
        self.content = content
        self.devices = devices
        self.permissions = permissions
    }

    // MARK: - Derived state

    var selectedDisplay: DisplayInfo? {
        displays.first { $0.id == selectedDisplayID } ?? displays.first
    }

    var selectedSource: CaptureSource? {
        switch sourceKind {
        case .display: selectedDisplay.map(CaptureSource.display)
        case .window: selectedWindow.map(CaptureSource.window)
        case .region: selectedRegion.map(CaptureSource.region)
        }
    }

    var canPerformPrimaryAction: Bool {
        selectedSource != nil
    }

    var screenRecordingStatus: PermissionStatus {
        permissions.status(of: .screenRecording)
    }

    var selectedCameraName: String? {
        let camera = settings.settings.camera
        guard camera.enabled else { return nil }
        return cameras.first { $0.id == camera.deviceID }?.name ?? cameras.first?.name
    }

    var selectedMicrophoneName: String? {
        let recording = settings.settings.recording
        guard recording.microphoneEnabled else { return nil }
        return microphones.first { $0.id == recording.microphoneDeviceID }?.name ?? microphones.first?.name
    }

    // MARK: - Loading

    func refresh() async {
        do {
            displays = try await content.displays()
        } catch {
            displays = []
            Log.ui.error("Display list failed: \(error.localizedDescription, privacy: .public)")
        }
        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first { $0.isMain }?.id ?? displays.first?.id
        }
        cameras = devices.cameras()
        microphones = devices.microphones()
        reconcileDeviceSelections()
    }

    /// Keeps stored device IDs pointing at devices that still exist.
    private func reconcileDeviceSelections() {
        if let id = settings.settings.camera.deviceID, !cameras.contains(where: { $0.id == id }) {
            settings.settings.camera.deviceID = nil
        }
        if let id = settings.settings.recording.microphoneDeviceID, !microphones.contains(where: { $0.id == id }) {
            settings.settings.recording.microphoneDeviceID = nil
        }
    }

    // MARK: - Device toggles

    func setCameraEnabled(_ enabled: Bool) {
        settings.settings.camera.enabled = enabled
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        settings.settings.recording.microphoneEnabled = enabled
    }

    // MARK: - Actions

    /// Record or capture, depending on the mode. Permission prompts happen here because this is a user action.
    func performPrimaryAction() async {
        guard let source = selectedSource else { return }
        var status = permissions.status(of: .screenRecording)
        if status == .notDetermined {
            status = await permissions.request(.screenRecording)
        }
        guard status.isAuthorized else {
            present(LibreScreenError.permissionDenied(.screenRecording))
            return
        }
        Log.ui.info("Primary action: \(self.mode.rawValue, privacy: .public) \(source.kind.rawValue, privacy: .public)")
    }

    /// Entry point for the menu bar and global hotkeys.
    func quickAction(mode: Mode, kind: SourceKind) async {
        self.mode = mode
        sourceKind = kind
        if displays.isEmpty {
            await refresh()
        }
        switch kind {
        case .display:
            await performPrimaryAction()
        case .window:
            chooseWindow()
        case .region:
            selectRegion()
        }
    }

    func chooseWindow() {
        Log.ui.debug("Window picker requested")
    }

    func selectRegion() {
        Log.ui.debug("Region selection requested")
    }

    // MARK: - Errors

    func present(_ error: any Error) {
        let libreError = error as? LibreScreenError
        var permission: Permission?
        if case let .permissionDenied(denied) = libreError {
            permission = denied
        }
        alert = AlertContent(
            title: error.localizedDescription,
            message: (error as? LocalizedError)?.recoverySuggestion ?? "",
            permission: permission
        )
    }
}
