// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

/// Open, reveal and copy for captures. Shared by the thumbnail panel and the Recents strip.
@MainActor
enum CaptureItemActions {
    static func open(_ item: CaptureItem) {
        NSWorkspace.shared.open(item.url)
    }

    static func revealInFinder(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Screenshots are copied as image and file; recordings as file only.
    static func copy(_ item: CaptureItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [item.url as NSURL]
        if item.kind == .screenshot, let image = NSImage(contentsOf: item.url) {
            objects.insert(image, at: 0)
        }
        pasteboard.writeObjects(objects)
    }
}
