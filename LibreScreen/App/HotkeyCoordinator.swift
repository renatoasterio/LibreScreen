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

    /// Re-registers observation after every change (the `withObservationTracking` callback fires once).
    /// `SettingsStore` keeps `onChange` alive until the next change, so it has to capture `self` weakly as
    /// well: a strong capture there would close the cycle self → settings → onChange → self.
    private func observe() {
        withObservationTracking {
            _ = settings.settings.hotkeys
        } onChange: { [weak self] in
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
