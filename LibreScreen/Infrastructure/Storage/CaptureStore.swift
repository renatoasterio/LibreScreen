// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Capture history as a JSON file in Application Support. Entries whose file disappeared are pruned on load.
actor CaptureStore: CaptureStoring {
    static let maximumItems = 200

    private let fileURL: URL
    private var cached: [CaptureItem]?

    private var fileManager: FileManager {
        .default
    }

    init(directory: URL? = nil) {
        let fileManager = FileManager.default
        let base = directory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "LibreScreen", directoryHint: .isDirectory)
            ?? fileManager.temporaryDirectory
        fileURL = base.appending(path: "captures.json")
    }

    func items() -> [CaptureItem] {
        if let cached {
            return cached
        }
        let loaded = load().filter { fileManager.fileExists(atPath: $0.url.path(percentEncoded: false)) }
        cached = loaded
        return loaded
    }

    func add(_ item: CaptureItem) {
        var current = items()
        current.removeAll { $0.id == item.id || $0.url == item.url }
        current.insert(item, at: 0)
        if current.count > Self.maximumItems {
            current.removeLast(current.count - Self.maximumItems)
        }
        cached = current
        save(current)
    }

    func remove(_ id: CaptureItem.ID, deletingFile: Bool) throws {
        var current = items()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        let item = current.remove(at: index)
        cached = current
        save(current)
        if deletingFile {
            try fileManager.trashItem(at: item.url, resultingItemURL: nil)
        }
    }

    private func load() -> [CaptureItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([CaptureItem].self, from: data)
        } catch {
            Log.storage.error("Capture history unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func save(_ items: [CaptureItem]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            Log.storage.error("Capture history could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
