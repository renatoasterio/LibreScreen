// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// Keeps the registered global shortcuts in sync with settings and routes them to app actions.
@MainActor
@Observable
final class HotkeyCoordinator {
    private(set) var failedActions: [HotkeyAction] = []

    private let registrar: any HotkeyRegistering
    private let settings: SettingsStore
    private var perform: (@MainActor (HotkeyAction) -> Void)?
    private var isActive = false

    init(registrar: any HotkeyRegistering, settings: SettingsStore) {
        self.registrar = registrar
        self.settings = settings
    }

    func activate(perform: @escaping @MainActor (HotkeyAction) -> Void) {
        guard !isActive else { return }
        isActive = true
        self.perform = perform
        observe()
        apply()
    }

    private func observe() {
        withObservationTracking {
            _ = settings.settings.hotkeys
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observe()
                self?.apply()
            }
        }
    }

    private func apply() {
        failedActions = registrar.apply(settings.settings.hotkeys) { [weak self] action in
            self?.perform?(action)
        }
    }
}
