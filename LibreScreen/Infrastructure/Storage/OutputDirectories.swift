// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Default folders under ~/Movies and ~/Pictures, unique sanitised file names, directories created on demand.
struct OutputDirectories: OutputLocating {
    /// FileManager is not Sendable; the shared instance is thread-safe for these calls.
    private var fileManager: FileManager {
        .default
    }

    var defaultRecordingsDirectory: URL {
        base(for: .moviesDirectory).appending(path: "LibreScreen", directoryHint: .isDirectory)
    }

    var defaultScreenshotsDirectory: URL {
        base(for: .picturesDirectory).appending(path: "LibreScreen", directoryHint: .isDirectory)
    }

    func recordingURL(container: VideoContainer, source: CaptureSource, directory: URL?, date: Date) throws -> URL {
        let folder = try prepared(directory ?? defaultRecordingsDirectory)
        let prefix = String(localized: "Gravação", comment: "File name prefix for recordings")
        let name = FileNaming.name(prefix: prefix, date: date, summary: source.summary)
        return uniqueURL(in: folder, name: name, ext: container.fileExtension)
    }

    func screenshotURL(format: ImageFormat, source: CaptureSource, directory: URL?, date: Date) throws -> URL {
        let folder = try prepared(directory ?? defaultScreenshotsDirectory)
        let prefix = String(localized: "Captura de Tela", comment: "File name prefix for screenshots")
        let name = FileNaming.name(prefix: prefix, date: date, summary: source.summary)
        return uniqueURL(in: folder, name: name, ext: format.fileExtension)
    }

    private func base(for directory: FileManager.SearchPathDirectory) -> URL {
        fileManager.urls(for: directory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
    }

    private func prepared(_ directory: URL) throws -> URL {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LibreScreenError.outputDirectoryUnavailable(path: directory.path(percentEncoded: false))
        }
        guard fileManager.isWritableFile(atPath: directory.path(percentEncoded: false)) else {
            throw LibreScreenError.outputDirectoryUnavailable(path: directory.path(percentEncoded: false))
        }
        return directory
    }

    private func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        var candidate = folder.appending(path: "\(name).\(ext)")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(name) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

/// Pure naming rules, unit-tested.
enum FileNaming {
    static let maximumSummaryLength = 40

    /// "Gravação 2026-10-21 22.30.15 – Finder". Characters that are illegal or confusing in file names are removed.
    static func name(prefix: String, date: Date, summary: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = formatter.string(from: date)
        let cleaned = sanitize(summary)
        return cleaned.isEmpty ? "\(prefix) \(stamp)" : "\(prefix) \(stamp) – \(cleaned)"
    }

    static func sanitize(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0}").union(.controlCharacters).union(.newlines)
        let filtered = text.unicodeScalars.filter { !forbidden.contains($0) }
        var result = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix(".") {
            result.removeFirst()
        }
        if result.count > maximumSummaryLength {
            result = String(result.prefix(maximumSummaryLength)).trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
