// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Grid of on-screen windows grouped by application, with live thumbnails and a search field.
struct WindowPickerSheet: View {
    @Bindable var hub: HubViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: DesignTokens.Spacing.md)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 780, height: 540)
        .task { await hub.loadWindows() }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("Escolher janela")
                .font(.title3.weight(.semibold))
            Spacer()
            TextField("Buscar", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button {
                Task { await hub.loadWindows() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Atualizar lista")
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(DesignTokens.Spacing.lg)
    }

    @ViewBuilder
    private var content: some View {
        if !hub.screenRecordingStatus.isAuthorized {
            ContentUnavailableView {
                Label("Gravação de Tela necessária", systemImage: "rectangle.dashed.badge.record")
            } description: {
                Text("Para listar janelas, permita a Gravação de Tela para o LibreScreen.")
            } actions: {
                Button("Permissões…") {
                    dismiss()
                    hub.isPresentingPermissions = true
                }
                .prominentGlassButtonStyle()
            }
        } else if hub.isLoadingWindows, hub.windows.isEmpty {
            ProgressView("Procurando janelas…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredGroups.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl, pinnedViews: []) {
                    ForEach(filteredGroups, id: \.name) { group in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            HStack(spacing: 6) {
                                if let icon = group.icon {
                                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                                }
                                Text(group.name).font(.headline)
                            }
                            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.md) {
                                ForEach(group.windows) { window in
                                    WindowCard(
                                        window: window,
                                        isSelected: hub.selectedWindow?.id == window.id,
                                        thumbnail: hub.windowThumbnail
                                    ) {
                                        hub.select(window)
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(DesignTokens.Spacing.lg)
            }
        }
    }

    private struct Group {
        let name: String
        let icon: NSImage?
        let windows: [WindowInfo]
    }

    private var filteredGroups: [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matching = hub.windows.filter { window in
            needle.isEmpty
                || window.title.localizedCaseInsensitiveContains(needle)
                || window.applicationName.localizedCaseInsensitiveContains(needle)
        }
        let grouped = Dictionary(grouping: matching, by: \.applicationName)
        return grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            let windows = grouped[name] ?? []
            let icon = windows.first.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon }
            return Group(name: name, icon: icon, windows: windows)
        }
    }
}

private struct WindowCard: View {
    let window: WindowInfo
    let isSelected: Bool
    let thumbnail: (WindowInfo) async -> CGImage?
    let action: () -> Void

    @State private var image: CGImage?
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                Text(window.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(DesignTokens.Spacing.sm)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: DesignTokens.Radius.md, tint: isSelected ? Color.accentColor : nil, interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .scaleEffect(isHovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .task(id: window.id) { image = await thumbnail(window) }
        .accessibilityLabel(Text("\(window.applicationName): \(window.displayTitle)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
