// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The user's background images: add with an open panel, pick one, remove from the context menu.
@MainActor
@Observable
final class BackgroundLibraryViewModel {
    private(set) var images: [URL] = []
    var errorMessage: String?

    private let store: any BackgroundImageStoring
    private let settings: SettingsStore

    init(store: any BackgroundImageStoring, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    var selected: URL? {
        settings.settings.camera.backgroundImageURL
    }

    func load() {
        images = store.images()
        if let selected, !images.contains(selected) {
            settings.settings.camera.backgroundImageURL = images.first
        }
    }

    func select(_ url: URL) {
        settings.settings.camera.backgroundImageURL = url
        settings.settings.camera.background = .image
    }

    /// Opens the panel; the chosen files are copied into the library and the first one becomes active.
    func addImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Adicionar")
        panel.message = String(localized: "Escolha uma ou mais imagens para usar como fundo da câmera.")
        guard panel.runModal() == .OK else { return }
        do {
            let imported = try store.importImages(from: panel.urls)
            load()
            if let first = imported.first {
                select(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ url: URL) {
        do {
            try store.remove(url)
        } catch {
            errorMessage = error.localizedDescription
        }
        load()
    }
}

struct BackgroundLibraryView: View {
    @Bindable var model: BackgroundLibraryViewModel
    let thumbnails: ThumbnailLoader

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: DesignTokens.Spacing.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if model.images.isEmpty {
                Text("Nenhuma imagem adicionada ainda.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
                    ForEach(model.images, id: \.self) { url in
                        BackgroundThumbnail(url: url, isSelected: model.selected == url, thumbnails: thumbnails) {
                            model.select(url)
                        }
                        .contextMenu {
                            Button("Remover", role: .destructive) { model.remove(url) }
                        }
                    }
                }
            }
            HStack {
                Button {
                    model.addImages()
                } label: {
                    Label("Adicionar imagens…", systemImage: "plus")
                }
                .glassButtonStyle()
                if let message = model.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .task { model.load() }
    }
}

private struct BackgroundThumbnail: View {
    let url: URL
    let isSelected: Bool
    let thumbnails: ThumbnailLoader
    let action: () -> Void

    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(height: 66)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.system(size: 16))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .task(id: url) { image = await thumbnails.thumbnail(forImageAt: url, maxPixelSize: 320) }
        .help(url.lastPathComponent)
        .accessibilityLabel(Text("Fundo \(url.deletingPathExtension().lastPathComponent)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
