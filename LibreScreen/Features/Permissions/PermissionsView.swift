// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Explains the three permissions and lets the user grant them one by one. Shown as the first-run
/// sheet and whenever a permission is missing. Nothing is requested until a button is pressed.
struct PermissionsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    let isOnboarding: Bool

    var body: some View {
        let model = container.permissionsViewModel
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            header
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Permission.allCases) { permission in
                    PermissionRow(permission: permission, status: model.status(of: permission)) {
                        Task { await model.request(permission) }
                    } openSettings: {
                        model.openSystemSettings(for: permission)
                    }
                }
            }
            if model.suggestsRelaunch, !model.status(of: .screenRecording).isAuthorized {
                relaunchNotice
            }
            HStack {
                Spacer()
                Button(isOnboarding ? "Começar" : "Concluído", action: finish)
                    .prominentGlassButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 520)
        .task { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "lock.shield")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(isOnboarding ? "Bem-vindo ao LibreScreen" : "Permissões")
                    .font(.title2.weight(.semibold))
                Text("O LibreScreen pede cada acesso somente quando você usa o recurso. Nada sai do seu Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var relaunchNotice: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.orange)
            Text("Depois de permitir a Gravação de Tela, o macOS exige que o app seja reaberto.")
                .font(.callout)
            Spacer()
            Button("Reabrir agora") { container.permissionsViewModel.relaunch() }
                .glassButtonStyle()
        }
        .padding(DesignTokens.Spacing.md)
        .glassSurface(cornerRadius: DesignTokens.Radius.md, tint: .orange)
    }

    private func finish() {
        if isOnboarding {
            container.settings.settings.general.hasCompletedOnboarding = true
        }
        dismiss()
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusView
        }
        .padding(DesignTokens.Spacing.md)
        .glassSurface(cornerRadius: DesignTokens.Radius.md)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .authorized:
            Label("Permitido", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
                .font(.callout)
        case .notDetermined:
            Button("Permitir", action: request)
                .prominentGlassButtonStyle()
        case .denied, .restricted:
            Button("Abrir Ajustes", action: openSettings)
                .glassButtonStyle()
        }
    }

    private var icon: String {
        switch permission {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .camera: "video"
        case .microphone: "mic"
        }
    }

    private var title: String {
        switch permission {
        case .screenRecording: String(localized: "Gravação de Tela")
        case .camera: String(localized: "Câmera")
        case .microphone: String(localized: "Microfone")
        }
    }

    private var detail: String {
        switch permission {
        case .screenRecording: String(localized: "Necessária para gravar e capturar a tela ou janelas.")
        case .camera: String(localized: "Somente quando a bolha da webcam está ligada.")
        case .microphone: String(localized: "Somente quando a narração está ligada.")
        }
    }
}
