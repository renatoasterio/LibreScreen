// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import Foundation
import Observation

/// State of one annotation editor window. Undo works on whole-document snapshots, which is simple
/// and exact for the small documents screenshots produce.
@MainActor
@Observable
final class EditorViewModel {
    let item: CaptureItem
    let image: CGImage
    private(set) var document: AnnotationDocument
    var tool: AnnotationTool = .arrow {
        didSet {
            if tool != .select {
                selectedID = nil
            }
            if tool != .crop {
                cropDraft = nil
            }
            commitTextIfNeeded()
        }
    }

    var style = AnnotationStyle()
    var selectedID: UUID?
    var zoom: CGFloat = 1
    private(set) var draft: Annotation?
    private(set) var cropDraft: CGRect?
    var textDraft: TextDraft?
    private(set) var isDirty = false
    var statusMessage: String?

    let undoManager = UndoManager()

    private let encoder: any ImageEncoding
    private let onSaved: @MainActor (CaptureItem) -> Void
    private var dragOrigin: CGPoint?
    private var dragLastPoint: CGPoint?
    private var draggedAnnotationOriginal: Annotation?

    struct TextDraft: Equatable {
        var id: UUID?
        var origin: CGPoint
        var text: String
    }

    init(item: CaptureItem, image: CGImage, encoder: any ImageEncoding, onSaved: @escaping @MainActor (CaptureItem) -> Void) {
        self.item = item
        self.image = image
        self.encoder = encoder
        self.onSaved = onSaved
        document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        undoManager.levelsOfUndo = 100
    }

    var canvasSize: CGSize {
        CGSize(width: document.visibleRect.width * zoom, height: document.visibleRect.height * zoom)
    }

    var selectedAnnotation: Annotation? {
        selectedID.flatMap { id in document.annotations.first { $0.id == id } }
    }

    // MARK: - Document changes with undo

    private func replaceDocument(_ new: AnnotationDocument, actionName: String) {
        let old = document
        guard old != new else { return }
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in target.replaceDocument(old, actionName: actionName) }
        }
        undoManager.setActionName(actionName)
        document = new
        isDirty = true
    }

    func undo() {
        undoManager.undo()
    }

    func redo() {
        undoManager.redo()
    }

    func deleteSelection() {
        guard let selectedID else { return }
        var new = document
        new.remove(id: selectedID)
        replaceDocument(new, actionName: String(localized: "Apagar marcação"))
        self.selectedID = nil
    }

    func clearAll() {
        var new = document
        new.annotations.removeAll()
        replaceDocument(new, actionName: String(localized: "Limpar marcações"))
        selectedID = nil
    }

    // MARK: - Drag handling (points in image pixels)

    func beginDrag(at point: CGPoint) {
        commitTextIfNeeded()
        dragOrigin = point
        dragLastPoint = point
        switch tool {
        case .select:
            selectedID = document.annotation(at: point, tolerance: 8 / zoom)?.id
            draggedAnnotationOriginal = selectedAnnotation
        case .crop:
            cropDraft = CGRect(origin: point, size: .zero)
        case .text:
            textDraft = TextDraft(id: nil, origin: point, text: "")
        case .number:
            var new = document
            new.add(Annotation(shape: .number(new.nextNumber, center: point), style: style))
            replaceDocument(new, actionName: String(localized: "Adicionar número"))
        case .arrow, .line, .rectangle, .ellipse, .freehand, .highlighter, .pixelate:
            draft = Annotation(shape: shape(from: point, to: point, points: [point]), style: style)
        }
    }

    func updateDrag(to point: CGPoint) {
        guard let origin = dragOrigin else { return }
        switch tool {
        case .select:
            guard
                let selectedID,
                let original = draggedAnnotationOriginal,
                let index = document.annotations.firstIndex(where: { $0.id == selectedID }) else { return }
            var moved = original
            moved.translate(by: point - origin)
            document.annotations[index] = moved
        case .crop:
            cropDraft = Annotation.rect(from: origin, to: point).intersection(CGRect(origin: .zero, size: document.imageSize))
        case .freehand, .highlighter:
            if var current = draft, case let .freehand(points) = current.shape {
                current.shape = .freehand(points + [point])
                draft = current
            } else if var current = draft, case let .highlighter(points) = current.shape {
                current.shape = .highlighter(points + [point])
                draft = current
            }
        case .arrow, .line, .rectangle, .ellipse, .pixelate:
            draft = Annotation(id: draft?.id ?? UUID(), shape: shape(from: origin, to: point, points: []), style: style)
        case .text, .number:
            break
        }
        dragLastPoint = point
    }

    func endDrag() {
        defer {
            dragOrigin = nil
            dragLastPoint = nil
            draggedAnnotationOriginal = nil
            draft = nil
        }
        switch tool {
        case .select:
            guard let original = draggedAnnotationOriginal, let moved = selectedAnnotation, original != moved else { return }
            var before = document
            if let index = before.annotations.firstIndex(where: { $0.id == original.id }) {
                before.annotations[index] = original
            }
            let after = document
            document = before
            replaceDocument(after, actionName: String(localized: "Mover marcação"))
        case .crop:
            break
        default:
            guard let draft, draft.bounds.width + draft.bounds.height > 6 else { return }
            var new = document
            new.add(draft)
            replaceDocument(new, actionName: String(localized: "Adicionar marcação"))
        }
    }

    private func shape(from: CGPoint, to: CGPoint, points: [CGPoint]) -> AnnotationShape {
        switch tool {
        case .arrow: .arrow(from: from, to: to)
        case .line: .line(from: from, to: to)
        case .rectangle: .rectangle(Annotation.rect(from: from, to: to))
        case .ellipse: .ellipse(Annotation.rect(from: from, to: to))
        case .pixelate: .pixelate(Annotation.rect(from: from, to: to))
        case .freehand: .freehand(points)
        case .highlighter: .highlighter(points)
        default: .line(from: from, to: to)
        }
    }

    // MARK: - Text

    func commitTextIfNeeded() {
        guard let textDraft else { return }
        self.textDraft = nil
        let text = textDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var new = document
        if let id = textDraft.id, let index = new.annotations.firstIndex(where: { $0.id == id }) {
            if text.isEmpty {
                new.annotations.remove(at: index)
            } else {
                new.annotations[index].shape = .text(text, origin: textDraft.origin)
            }
            replaceDocument(new, actionName: String(localized: "Editar texto"))
        } else if !text.isEmpty {
            new.add(Annotation(shape: .text(text, origin: textDraft.origin), style: style))
            replaceDocument(new, actionName: String(localized: "Adicionar texto"))
        }
    }

    func editText(of annotation: Annotation) {
        guard case let .text(text, origin) = annotation.shape else { return }
        tool = .text
        textDraft = TextDraft(id: annotation.id, origin: origin, text: text)
    }

    // MARK: - Crop

    func applyCrop() {
        guard let cropDraft, cropDraft.width >= 2, cropDraft.height >= 2 else { return }
        var new = document
        new.applyCrop(cropDraft)
        replaceDocument(new, actionName: String(localized: "Recortar"))
        self.cropDraft = nil
        tool = .select
    }

    func cancelCrop() {
        cropDraft = nil
    }

    func resetCrop() {
        var new = document
        new.cropRect = nil
        replaceDocument(new, actionName: String(localized: "Desfazer recorte"))
    }

    // MARK: - Output

    func renderedImage() -> CGImage? {
        commitTextIfNeeded()
        return AnnotationRenderer.render(document: document, base: image)
    }

    func copyToClipboard() {
        guard let rendered = renderedImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))])
        statusMessage = String(localized: "Copiado para a área de transferência")
    }

    /// Overwrites the screenshot file in place.
    func save() throws {
        guard let rendered = renderedImage() else { return }
        let format: ImageFormat = item.url.pathExtension.lowercased() == "png" ? .png : .jpeg
        try encoder.write(rendered, to: item.url, format: format, quality: 0.9)
        isDirty = false
        statusMessage = String(localized: "Salvo")
        onSaved(item)
    }

    func save(to url: URL, format: ImageFormat) throws {
        guard let rendered = renderedImage() else { return }
        try encoder.write(rendered, to: url, format: format, quality: 0.9)
        statusMessage = String(localized: "Salvo em \(url.lastPathComponent)")
    }

    #if DEBUG
    /// Adds an annotation without touching the undo stack (snapshot tooling only).
    func replaceForSnapshot(_ annotation: Annotation) {
        document.add(annotation)
    }
    #endif

    func fitZoom(in size: CGSize) {
        let visible = document.visibleRect.size
        guard visible.width > 0, visible.height > 0, size.width > 0, size.height > 0 else { return }
        zoom = min(1, min((size.width - 40) / visible.width, (size.height - 40) / visible.height))
    }
}
