// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// Persists `AppSettings` as JSON in `UserDefaults`, validating on load and saving on every change.
@MainActor
@Observable
final class SettingsStore: SettingsStoring {
    static let key = "br.com.asoft.LibreScreen.settings"

    private let defaults: UserDefaults

    var settings: AppSettings {
        didSet {
            if oldValue != settings {
                persist()
            }
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = Self.load(from: defaults).validated()
    }

    private static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Log.storage.error("Settings could not be decoded, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.key)
        } catch {
            Log.storage.error("Settings could not be encoded: \(error.localizedDescription, privacy: .public)")
        }
    }
}
