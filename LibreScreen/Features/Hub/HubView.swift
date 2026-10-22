// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// The main window content: pick a mode, a source and devices, then record or capture.
struct HubView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var hub = container.hub
        VStack(spacing: DesignTokens.Spacing.xl) {
            header
            ModePicker(selection: $hub.mode)
            SourceKindPicker(selection: $hub.sourceKind)
            SourceControls(hub: hub)
            if hub.mode == .record {
                DeviceControls(hub: hub)
            }
            PrimaryActionButton(hub: hub)
            if !hub.recents.isEmpty {
                RecentsStrip(hub: hub)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Spacing.xxl)
        .frame(width: DesignTokens.hubWidth)
        .task { await hub.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            Task { await hub.refresh() }
        }
        .alert(
            hub.alert?.title ?? "",
            isPresented: Binding(get: { hub.alert != nil }, set: {
                if !$0 {
                    hub.alert = nil
                }
            }),
            presenting: hub.alert
        ) { content in
            if let permission = content.permission {
                Button("Abrir Ajustes do Sistema") { container.permissions.openSystemSettings(for: permission) }
            }
            Button("OK", role: .cancel) {}
        } message: { content in
            Text(content.message)
        }
        .sheet(isPresented: $hub.isPresentingPermissions) {
            PermissionsView(isOnboarding: false)
                .environment(container)
        }
        .sheet(isPresented: $hub.isPresentingWindowPicker) {
            WindowPickerSheet(hub: hub)
        }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
            Text("LibreScreen")
                .font(.title3.weight(.semibold))
            Spacer()
            PermissionStatusButton(status: container.hub.screenRecordingStatus) {
                container.hub.isPresentingPermissions = true
            }
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Configurações")
            .accessibilityLabel("Configurações")
        }
    }
}

/// A small status dot that opens the permissions sheet.
private struct PermissionStatusButton: View {
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassSurface(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .help("Permissões de gravação, câmera e microfone")
        .accessibilityLabel(Text("Permissões: \(title)"))
    }

    private var color: Color {
        switch status {
        case .authorized: .green
        case .notDetermined: .orange
        case .denied, .restricted: .red
        }
    }

    private var title: String {
        switch status {
        case .authorized: String(localized: "Pronto para gravar")
        case .notDetermined: String(localized: "Permissões pendentes")
        case .denied, .restricted: String(localized: "Gravação de tela negada")
        }
    }
}

private struct PrimaryActionButton: View {
    @Bindable var hub: HubViewModel

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                Task { await hub.performPrimaryAction() }
            } label: {
                Label(title, systemImage: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .prominentGlassButtonStyle()
            .tint(hub.mode == .record || isActive ? DesignTokens.recordRed : Color.accentColor)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!hub.canPerformPrimaryAction)
            .accessibilityHint(hub.mode == .record ? "Inicia a gravação" : "Tira a captura de tela")

            Text(hint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var isActive: Bool {
        hub.recording.phase.isActive
    }

    private var title: String {
        switch hub.recording.phase {
        case .recording, .paused:
            return String(localized: "Parar gravação")
        case .preparing, .countdown:
            return String(localized: "Preparando…")
        case .finishing:
            return String(localized: "Salvando…")
        case .idle:
            if hub.mode == .record {
                return String(localized: "Gravar")
            }
            return String(localized: "Capturar")
        }
    }

    private var symbol: String {
        if hub.recording.isRecordingOrPaused {
            return "stop.fill"
        }
        return hub.mode == .record ? "record.circle.fill" : "camera.fill"
    }

    private var hint: String {
        if hub.recording.isRecordingOrPaused {
            return String(localized: "⌘R · Para e salva a gravação")
        }
        switch hub.sourceKind {
        case .display: return String(localized: "⌘R · Grava o monitor inteiro")
        case .window: return String(localized: "⌘R · Grava somente a janela escolhida")
        case .region: return String(localized: "⌘R · Grava a área selecionada")
        }
    }
}
