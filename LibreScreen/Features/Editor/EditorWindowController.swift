// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// One editor window per screenshot. Supplies the view model's `UndoManager` to the responder chain so
/// the Edit menu's Undo/Redo work, and asks before closing with unsaved changes.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorViewModel
    var onClose: (@MainActor (EditorWindowController) -> Void)?

    init(model: EditorViewModel) {
        self.model = model
        let hosting = NSHostingController(rootView: EditorView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = model.item.url.lastPathComponent
        window.representedURL = model.item.url
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.center()
        window.setFrameAutosaveName("EditorWindow")
        window.sharingType = .none
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        model.undoManager
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Salvar as marcações?")
        alert.informativeText = String(localized: "As alterações serão gravadas no arquivo da captura.")
        alert.addButton(withTitle: String(localized: "Salvar"))
        alert.addButton(withTitle: String(localized: "Descartar"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try model.save()
                return true
            } catch {
                model.statusMessage = error.localizedDescription
                return false
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}
