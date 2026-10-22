// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

@MainActor
protocol SettingsStoring: AnyObject {
    var settings: AppSettings { get set }
}
