// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import OSLog

/// One logger per subsystem area. Paths, window titles and device names must be logged with
/// `privacy: .private`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "br.com.asoft.LibreScreen"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let writer = Logger(subsystem: subsystem, category: "writer")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let editor = Logger(subsystem: subsystem, category: "editor")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
