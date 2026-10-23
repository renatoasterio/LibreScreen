// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Virtual-background images copied into Application Support, so a chosen background keeps working
/// even when the original file moves. Only files ImageIO can decode are accepted.
struct BackgroundLibrary: BackgroundImageStoring {
    private var fileManager: FileManager {
        .default
    }

    var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return base.appending(path: "LibreScreen/Backgrounds", directoryHint: .isDirectory)
    }

    func images() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return [] }
        return entries
            .filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return values?.isRegularFile == true && Self.isImage(url)
            }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
    }

    func importImages(from urls: [URL]) throws -> [URL] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var imported: [URL] = []
        for source in urls where Self.isImage(source) {
            let name = FileNaming.sanitize(source.deletingPathExtension().lastPathComponent)
            let base = name.isEmpty ? "Fundo" : name
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
            var target = directory.appending(path: "\(base).\(ext)")
            var counter = 2
            while fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
                target = directory.appending(path: "\(base) \(counter).\(ext)")
                counter += 1
            }
            try fileManager.copyItem(at: source, to: target)
            imported.append(target)
        }
        return imported
    }

    func remove(_ url: URL) throws {
        // Only files inside the library are ever deleted.
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path.hasPrefix(directory.standardizedFileURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: url)
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) else { return false }
        return UTType(type as String)?.conforms(to: .image) ?? false
    }
}
