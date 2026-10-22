// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Horizontal strip of the latest captures with open/reveal/copy/delete actions.
struct RecentsStrip: View {
    @Bindable var hub: HubViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Recentes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: DesignTokens.Spacing.sm + 2) {
                    ForEach(hub.recents) { item in
                        RecentCard(item: item, loader: hub.thumbnails) {
                            hub.open(item)
                        }
                        .contextMenu {
                            Button("Abrir") { hub.open(item) }
                            Button("Mostrar no Finder") { CaptureItemActions.revealInFinder(item) }
                            Button("Copiar") { CaptureItemActions.copy(item) }
                            Divider()
                            Button("Apagar", role: .destructive) { Task { await hub.remove(item) } }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capturas recentes")
    }
}

private struct RecentCard: View {
    let item: CaptureItem
    let loader: ThumbnailLoader
    let action: () -> Void

    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 124, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                badge
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .task(id: item.url) { image = await loader.thumbnail(for: item, maxPixelSize: 260) }
        .help(item.url.lastPathComponent)
        .accessibilityLabel(Text(item.kind == .recording ? "Gravação \(item.sourceSummary)" : "Captura \(item.sourceSummary)"))
    }

    @ViewBuilder
    private var badge: some View {
        if let duration = item.duration {
            Text(duration.recordingClock)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
        } else {
            Image(systemName: "camera.fill")
                .font(.caption2)
                .padding(4)
                .background(.black.opacity(0.6), in: Circle())
                .foregroundStyle(.white)
        }
    }
}
