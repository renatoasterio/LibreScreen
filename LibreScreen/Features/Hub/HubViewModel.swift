// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
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
    var isPresentingWindowPicker = false

    private(set) var displays: [DisplayInfo] = []
    private(set) var windows: [WindowInfo] = []
    private(set) var isLoadingWindows = false
    private(set) var cameras: [MediaDevice] = []
    private(set) var microphones: [MediaDevice] = []
    private(set) var recents: [CaptureItem] = []

    let settings: SettingsStore
    let recording: RecordingViewModel
    let screenshot: ScreenshotViewModel
    let thumbnails: ThumbnailLoader
    weak var regionSelector: (any RegionSelecting)?
    weak var editorOpener: (any EditorOpening)?
    private let content: any ShareableContentProviding
    private let devices: any MediaDeviceProviding
    private let permissions: any PermissionsChecking
    private let captures: any CaptureStoring

    init(
        settings: SettingsStore,
        content: any ShareableContentProviding,
        devices: any MediaDeviceProviding,
        permissions: any PermissionsChecking,
        captures: any CaptureStoring,
        recording: RecordingViewModel,
        screenshot: ScreenshotViewModel,
        thumbnails: ThumbnailLoader
    ) {
        self.settings = settings
        self.content = content
        self.devices = devices
        self.permissions = permissions
        self.captures = captures
        self.recording = recording
        self.screenshot = screenshot
        self.thumbnails = thumbnails
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
        if recording.isRecordingOrPaused {
            return true
        }
        guard recording.phase == .idle, !screenshot.isCapturing else { return false }
        // A region can always be drawn on demand.
        return selectedSource != nil || sourceKind == .region
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
        await refreshRecents()
    }

    func refreshRecents() async {
        recents = await captures.items()
    }

    func loadWindows() async {
        isLoadingWindows = true
        defer { isLoadingWindows = false }
        do {
            windows = try await content.windows()
            if let selected = selectedWindow, !windows.contains(where: { $0.id == selected.id }) {
                selectedWindow = nil
            }
        } catch {
            present(error)
        }
    }

    func windowThumbnail(_ window: WindowInfo) async -> CGImage? {
        try? await content.thumbnail(for: .window(window), maxPixelSize: 480)
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

    // MARK: - Selection

    func select(_ window: WindowInfo) {
        selectedWindow = window
        sourceKind = .window
        isPresentingWindowPicker = false
    }

    func chooseWindow() {
        isPresentingWindowPicker = true
    }

    /// Shows the per-display overlay; the result becomes the selected region or window.
    @discardableResult
    func selectRegion() async -> Bool {
        guard let regionSelector else { return false }
        if displays.isEmpty {
            await refresh()
        }
        await loadWindows()
        guard let result = await regionSelector.selectRegion(displays: displays, windows: windows) else { return false }
        switch result {
        case let .region(region):
            selectedRegion = region
            sourceKind = .region
        case let .window(window):
            selectedWindow = window
            sourceKind = .window
        }
        return true
    }

    // MARK: - Actions

    /// Record, stop or capture depending on the state. Permission prompts happen inside the use cases.
    func performPrimaryAction() async {
        if recording.isRecordingOrPaused {
            await recording.stop()
            return
        }
        guard recording.phase == .idle, !screenshot.isCapturing else { return }
        if sourceKind == .region, selectedRegion == nil {
            guard await selectRegion() else { return }
        }
        guard let source = selectedSource else { return }
        switch mode {
        case .record:
            await recording.start(source: source)
        case .screenshot:
            await screenshot.capture(source: source)
        }
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
            // Like ⌘⇧4: a fresh selection, then capture or record immediately.
            selectedRegion = nil
            guard await selectRegion() else { return }
            await performPrimaryAction()
        }
    }

    func open(_ item: CaptureItem) {
        if item.kind == .screenshot, let editorOpener {
            editorOpener.openEditor(for: item, image: nil)
        } else {
            CaptureItemActions.open(item)
        }
    }

    func remove(_ item: CaptureItem) async {
        do {
            try await captures.remove(item.id, deletingFile: true)
            await thumbnails.invalidate(item.url)
        } catch {
            present(error)
        }
        await refreshRecents()
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
