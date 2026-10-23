// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Camera, microphone and system-audio chips. Each chip is a menu with a toggle and device choices.
struct DeviceControls: View {
    @Bindable var hub: HubViewModel

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            cameraChip
            microphoneChip
            systemAudioChip
        }
    }

    private var cameraChip: some View {
        @Bindable var store = hub.settings
        return DeviceChip(
            icon: "video.fill",
            title: String(localized: "Câmera"),
            isOn: store.settings.camera.enabled,
            subtitle: hub.selectedCameraName
        ) {
            Toggle("Incluir câmera na gravação", isOn: $store.settings.camera.enabled)
            if !hub.cameras.isEmpty {
                Divider()
                Picker("Dispositivo", selection: $store.settings.camera.deviceID) {
                    ForEach(hub.cameras) { camera in
                        Text(camera.name).tag(Optional(camera.id))
                    }
                }
            }
            Divider()
            Picker("Fundo", selection: $store.settings.camera.background) {
                Text("Nenhum").tag(CameraBackgroundMode.none)
                Text("Desfoque").tag(CameraBackgroundMode.blur)
                Text("Imagem").tag(CameraBackgroundMode.image)
            }
            Toggle("Espelhar imagem", isOn: $store.settings.camera.mirrored)
        }
    }

    private var microphoneChip: some View {
        @Bindable var store = hub.settings
        return DeviceChip(
            icon: "mic.fill",
            title: String(localized: "Microfone"),
            isOn: store.settings.recording.microphoneEnabled,
            subtitle: hub.selectedMicrophoneName
        ) {
            Toggle("Gravar microfone", isOn: $store.settings.recording.microphoneEnabled)
            if !hub.microphones.isEmpty {
                Divider()
                Picker("Dispositivo", selection: $store.settings.recording.microphoneDeviceID) {
                    ForEach(hub.microphones) { microphone in
                        Text(microphone.name).tag(Optional(microphone.id))
                    }
                }
            }
        }
    }

    private var systemAudioChip: some View {
        @Bindable var store = hub.settings
        return DeviceChip(
            icon: "speaker.wave.2.fill",
            title: String(localized: "Som do sistema"),
            isOn: store.settings.recording.capturesSystemAudio,
            subtitle: nil
        ) {
            Toggle("Gravar áudio do sistema", isOn: $store.settings.recording.capturesSystemAudio)
        }
    }
}

private struct DeviceChip<Content: View>: View {
    let icon: String
    let title: String
    let isOn: Bool
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle ?? (isOn ? String(localized: "Ligado") : String(localized: "Desligado")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassSurface(cornerRadius: 14, tint: isOn ? Color.accentColor : nil, interactive: true)
        .accessibilityLabel(Text("\(title): \(subtitle ?? (isOn ? String(localized: "Ligado") : String(localized: "Desligado")))"))
    }
}
