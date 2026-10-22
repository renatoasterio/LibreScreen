// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreImage
import MetalKit
import SwiftUI

/// Metal-backed live preview of processed camera frames, masked to the bubble shape.
struct CameraPreviewView: NSViewRepresentable {
    let source: any CameraFrameSource
    let shape: OverlayShape

    func makeNSView(context: Context) -> CameraMetalView {
        let view = CameraMetalView()
        view.start(source: source)
        return view
    }

    func updateNSView(_ nsView: CameraMetalView, context: Context) {
        nsView.shape = shape
    }

    static func dismantleNSView(_ nsView: CameraMetalView, coordinator: ()) {
        nsView.stop()
    }
}

@MainActor
final class CameraMetalView: MTKView {
    var shape: OverlayShape = .circle

    private var context: CIContext?
    private var commandQueue: MTLCommandQueue?
    private var latest: CIImage?
    private var consumer: Task<Void, Never>?
    private var maskCache: (size: CGSize, shape: OverlayShape, mask: CIImage)?

    init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)
        if let metalDevice {
            context = CIContext(mtlDevice: metalDevice, options: [.cacheIntermediates: false])
            commandQueue = metalDevice.makeCommandQueue()
        }
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isPaused = true
        enableSetNeedsDisplay = true
        layer?.isOpaque = false
        wantsLayer = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func start(source: any CameraFrameSource) {
        consumer?.cancel()
        consumer = Task { [weak self] in
            for await frame in source.frames() {
                guard let self, !Task.isCancelled else { return }
                latest = frame.image
                needsDisplay = true
            }
        }
    }

    func stop() {
        consumer?.cancel()
        consumer = nil
        latest = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let image = latest,
            let context,
            let commandQueue,
            let drawable = currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let target = CGSize(width: drawableSize.width, height: drawableSize.height)
        guard target.width > 0, target.height > 0 else { return }

        let scale = max(target.width / image.extent.width, target.height / image.extent.height)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGPoint(x: (target.width - scaled.extent.width) / 2, y: (target.height - scaled.extent.height) / 2)
        let bounds = CGRect(origin: .zero, size: target)
        let masked = scaled
            .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
            .cropped(to: bounds)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask(for: target)
            ])
            .cropped(to: bounds)

        let destination = CIRenderDestination(
            width: Int(target.width),
            height: Int(target.height),
            pixelFormat: colorPixelFormat,
            commandBuffer: commandBuffer
        ) { drawable.texture }
        destination.isFlipped = false
        destination.alphaMode = .premultiplied
        do {
            try context.startTask(toClear: destination)
            try context.startTask(toRender: masked, to: destination)
        } catch {
            Log.camera.error("Preview render failed: \(error.localizedDescription, privacy: .public)")
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func mask(for size: CGSize) -> CIImage {
        if let maskCache, maskCache.size == size, maskCache.shape == shape {
            return maskCache.mask
        }
        var settings = CameraOverlaySettings()
        settings.shape = shape
        let side = min(size.width, size.height)
        let key = OverlayArtwork.Key(side: Int(side), radius: Int(settings.cornerRadius(forSide: side)), border: false, shadow: false)
        let mask = OverlayArtwork.make(key: key).mask
        maskCache = (size, shape, mask)
        return mask
    }
}
