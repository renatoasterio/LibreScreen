// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// The zoomable image with annotations, drawn by `AnnotationRenderer` through a Core Graphics context.
struct AnnotationCanvasView: View {
    @Bindable var model: EditorViewModel
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                canvas
                    .frame(width: model.canvasSize.width, height: model.canvasSize.height)
                    .gesture(dragGesture)
                    .onTapGesture(count: 2) { location in
                        let point = imagePoint(from: location)
                        if let annotation = model.document.annotation(at: point, tolerance: 8 / model.zoom), case .text = annotation.shape {
                            model.editText(of: annotation)
                            textFieldFocused = true
                        }
                    }
                if let draft = model.textDraft {
                    textEditor(for: draft)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onDeleteCommand { model.deleteSelection() }
        .accessibilityLabel("Área de edição")
    }

    private var canvas: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            context.withCGContext { cg in
                let visible = model.document.visibleRect
                cg.scaleBy(x: model.zoom, y: model.zoom)
                cg.translateBy(x: -visible.minX, y: -visible.minY)
                cg.clip(to: visible)
                AnnotationRenderer.drawBase(model.image, in: cg)
                AnnotationRenderer.draw(model.document.annotations, base: model.image, in: cg)
                if let draft = model.draft {
                    AnnotationRenderer.draw([draft], base: model.image, in: cg)
                }
                drawSelection(in: cg)
                drawCropDraft(in: cg, visible: visible)
            }
        }
        .pointerStyle(model.tool == .text ? .horizontalText : .default)
    }

    private func drawSelection(in cg: CGContext) {
        guard let selected = model.selectedAnnotation else { return }
        let rect = selected.bounds.insetBy(dx: -4, dy: -4)
        cg.setStrokeColor(CGColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 0.9))
        cg.setLineWidth(1.5 / model.zoom)
        cg.setLineDash(phase: 0, lengths: [6 / model.zoom, 4 / model.zoom])
        cg.stroke(rect)
        cg.setLineDash(phase: 0, lengths: [])
    }

    private func drawCropDraft(in cg: CGContext, visible: CGRect) {
        guard model.tool == .crop, let crop = model.cropDraft, crop.width > 1, crop.height > 1 else { return }
        cg.setFillColor(CGColor(gray: 0, alpha: 0.45))
        cg.addRect(visible)
        cg.addRect(crop)
        cg.fillPath(using: .evenOdd)
        cg.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        cg.setLineWidth(1.5 / model.zoom)
        cg.stroke(crop)
        let handle = 7 / model.zoom
        cg.setFillColor(CGColor(gray: 1, alpha: 1))
        for point in [
            crop.origin,
            CGPoint(x: crop.maxX, y: crop.minY),
            CGPoint(x: crop.minX, y: crop.maxY),
            CGPoint(x: crop.maxX, y: crop.maxY)
        ] {
            cg.fillEllipse(in: CGRect(x: point.x - handle / 2, y: point.y - handle / 2, width: handle, height: handle))
        }
    }

    private func textEditor(for draft: EditorViewModel.TextDraft) -> some View {
        let visible = model.document.visibleRect
        let origin = CGPoint(x: (draft.origin.x - visible.minX) * model.zoom, y: (draft.origin.y - visible.minY) * model.zoom)
        return TextField("Texto", text: Binding(
            get: { model.textDraft?.text ?? "" },
            set: { model.textDraft?.text = $0 }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: model.style.fontSize * model.zoom, weight: .bold))
        .foregroundStyle(Color(cgColor: AnnotationRenderer.cgColor(model.style.color)))
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .frame(minWidth: 120)
        .fixedSize()
        .offset(x: origin.x, y: origin.y)
        .focused($textFieldFocused)
        .onSubmit { model.commitTextIfNeeded() }
        .onExitCommand { model.textDraft = nil }
        .onAppear { textFieldFocused = true }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = imagePoint(from: value.location)
                if value.translation == .zero, model.draft == nil, model.cropDraft == nil || model.tool != .crop {
                    model.beginDrag(at: imagePoint(from: value.startLocation))
                }
                model.updateDrag(to: point)
            }
            .onEnded { _ in
                model.endDrag()
            }
    }

    private func imagePoint(from location: CGPoint) -> CGPoint {
        let visible = model.document.visibleRect
        return CGPoint(x: location.x / model.zoom + visible.minX, y: location.y / model.zoom + visible.minY)
    }
}
