// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Keeps an AppKit window's height in step with its SwiftUI content (anchored at the top edge),
/// so the hub grows and shrinks smoothly when sections such as Recents appear.
struct WindowContentSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> SizerView {
        SizerView()
    }

    func updateNSView(_ nsView: SizerView, context: Context) {
        nsView.scheduleResize()
    }

    @MainActor
    final class SizerView: NSView {
        private var isScheduled = false

        func scheduleResize() {
            guard !isScheduled else { return }
            isScheduled = true
            Task { @MainActor [weak self] in
                self?.isScheduled = false
                self?.resizeWindowToFit()
            }
        }

        private func resizeWindowToFit() {
            guard let window, let content = window.contentView, !window.inLiveResize else { return }
            let fitting = content.fittingSize
            guard fitting.height > 0, abs(fitting.height - content.frame.height) > 1 else { return }
            var frame = window.frame
            frame.origin.y += content.frame.height - fitting.height
            frame.size.height += fitting.height - content.frame.height
            window.setFrame(frame, display: true, animate: true)
        }
    }
}
