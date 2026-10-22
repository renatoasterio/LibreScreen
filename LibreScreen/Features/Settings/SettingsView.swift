// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Geral", systemImage: "gearshape") }
            VideoSettingsTab()
                .tabItem { Label("Vídeo", systemImage: "film") }
            AudioSettingsTab()
                .tabItem { Label("Áudio", systemImage: "waveform") }
            CameraSettingsTab()
                .tabItem { Label("Câmera", systemImage: "video") }
            ScreenshotSettingsTab()
                .tabItem { Label("Capturas", systemImage: "camera.viewfinder") }
            AboutTab()
                .tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 540)
    }
}

// MARK: - Geral

struct GeneralSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var store = container.settings
        Form {
            Section("Aparência") {
                Toggle("Mostrar ícone no Dock", isOn: $store.settings.general.showsInDock)
                    .onChange(of: store.settings.general.showsInDock) { _, newValue in
                        container.windows.applyActivationPolicy(showsInDock: newValue)
                    }
                Toggle("Mostrar na barra de menus", isOn: $store.settings.general.showsMenuBarExtra)
            }
            Section("Depois de capturar") {
                Toggle("Mostrar miniatura flutuante", isOn: $store.settings.general.showsThumbnailPanel)
                Toggle("Revelar gravações no Finder", isOn: $store.settings.general.revealsInFinderAfterRecording)
                Toggle("Reproduzir sons", isOn: $store.settings.general.playsSounds)
            }
            Section("Pastas") {
                FolderRow(
                    title: String(localized: "Gravações"),
                    url: store.settings.recording.outputDirectory,
                    defaultURL: container.output.defaultRecordingsDirectory
                ) { store.settings.recording.outputDirectory = $0 }
                FolderRow(
                    title: String(localized: "Capturas de tela"),
                    url: store.settings.screenshot.outputDirectory,
                    defaultURL: container.output.defaultScreenshotsDirectory
                ) { store.settings.screenshot.outputDirectory = $0 }
            }
        }
        .formStyle(.grouped)
    }
}

/// A folder picker row backed by `NSOpenPanel`.
struct FolderRow: View {
    let title: String
    let url: URL?
    let defaultURL: URL
    let onChange: (URL?) -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text((url ?? defaultURL).path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 220, alignment: .trailing)
                Button("Escolher…", action: choose)
                if url != nil {
                    Button("Padrão") { onChange(nil) }
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url ?? defaultURL
        panel.prompt = String(localized: "Escolher")
        if panel.runModal() == .OK, let chosen = panel.url {
            onChange(chosen)
        }
    }
}

// MARK: - Vídeo

struct VideoSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var store = container.settings
        Form {
            Section("Arquivo") {
                Picker("Formato", selection: $store.settings.recording.container) {
                    Text("MP4").tag(VideoContainer.mp4)
                    Text("MOV").tag(VideoContainer.mov)
                }
                Picker("Codec", selection: $store.settings.recording.codec) {
                    Text("H.264 (compatível)").tag(VideoCodec.h264)
                    Text("HEVC (menor)").tag(VideoCodec.hevc)
                }
                Picker("Qualidade", selection: $store.settings.recording.quality) {
                    Text("Padrão").tag(VideoQuality.standard)
                    Text("Alta").tag(VideoQuality.high)
                    Text("Máxima").tag(VideoQuality.maximum)
                }
            }
            Section("Captura") {
                Picker("Quadros por segundo", selection: $store.settings.recording.frameRate) {
                    Text("30 fps").tag(FrameRate.fps30)
                    Text("60 fps").tag(FrameRate.fps60)
                }
                Picker("Resolução", selection: $store.settings.recording.resolution) {
                    Text("Nativa (Retina)").tag(ResolutionScale.native)
                    Text("Reduzida (1×)").tag(ResolutionScale.points)
                }
                Toggle("Mostrar cursor", isOn: $store.settings.recording.showsCursor)
                Picker("Contagem regressiva", selection: $store.settings.recording.countdownSeconds) {
                    ForEach(RecordingSettings.allowedCountdowns, id: \.self) { seconds in
                        Text(seconds == 0 ? String(localized: "Desligada") : String(localized: "\(seconds) s")).tag(seconds)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Áudio

struct AudioSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var store = container.settings
        Form {
            Section("Microfone") {
                Toggle("Gravar microfone por padrão", isOn: $store.settings.recording.microphoneEnabled)
                Picker("Dispositivo", selection: $store.settings.recording.microphoneDeviceID) {
                    Text("Padrão do sistema").tag(String?.none)
                    ForEach(container.hub.microphones) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
            }
            Section("Áudio do sistema") {
                Toggle("Gravar áudio do sistema por padrão", isOn: $store.settings.recording.capturesSystemAudio)
                Text("Microfone e áudio do sistema são gravados em trilhas separadas, prontos para edição.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await container.hub.refresh() }
    }
}

// MARK: - Câmera

struct CameraSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        Form {
            deviceSection
            bubbleSection
            backgroundSection
        }
        .formStyle(.grouped)
        .task { await container.hub.refresh() }
    }

    private var deviceSection: some View {
        @Bindable var store = container.settings
        return Section("Dispositivo") {
            Toggle("Incluir câmera por padrão", isOn: $store.settings.camera.enabled)
            Picker("Câmera", selection: $store.settings.camera.deviceID) {
                Text("Padrão").tag(String?.none)
                ForEach(container.hub.cameras) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            Toggle("Espelhar imagem", isOn: $store.settings.camera.mirrored)
        }
    }

    private var bubbleSection: some View {
        @Bindable var store = container.settings
        return Section("Bolha") {
            Picker("Formato", selection: $store.settings.camera.shape) {
                Text("Círculo").tag(OverlayShape.circle)
                Text("Retângulo arredondado").tag(OverlayShape.roundedRectangle)
            }
            Picker("Tamanho", selection: $store.settings.camera.size) {
                Text("Pequena").tag(OverlaySize.small)
                Text("Média").tag(OverlaySize.medium)
                Text("Grande").tag(OverlaySize.large)
            }
            Picker("Posição", selection: $store.settings.camera.corner) {
                Text("Canto superior esquerdo").tag(OverlayCorner.topLeft)
                Text("Canto superior direito").tag(OverlayCorner.topRight)
                Text("Canto inferior esquerdo").tag(OverlayCorner.bottomLeft)
                Text("Canto inferior direito").tag(OverlayCorner.bottomRight)
            }
            Toggle("Borda", isOn: $store.settings.camera.showsBorder)
            Toggle("Sombra", isOn: $store.settings.camera.showsShadow)
        }
    }

    private var backgroundSection: some View {
        @Bindable var store = container.settings
        return Section("Fundo") {
            Toggle("Desfocar fundo", isOn: $store.settings.camera.blurEnabled)
            Slider(value: $store.settings.camera.blurIntensity, in: 0 ... 1) {
                Text("Intensidade")
            } minimumValueLabel: {
                Image(systemName: "circle.lefthalf.filled")
            } maximumValueLabel: {
                Image(systemName: "circle.fill")
            }
            .disabled(!store.settings.camera.blurEnabled)
            Text("A separação entre você e o fundo é feita no próprio Mac, com o Vision.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Capturas

struct ScreenshotSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var store = container.settings
        Form {
            Section("Arquivo") {
                Picker("Formato", selection: $store.settings.screenshot.format) {
                    Text("PNG").tag(ImageFormat.png)
                    Text("JPEG").tag(ImageFormat.jpeg)
                }
                if store.settings.screenshot.format == .jpeg {
                    Slider(value: $store.settings.screenshot.jpegQuality, in: 0.3 ... 1) {
                        Text("Qualidade JPEG")
                    }
                }
                Picker("Resolução", selection: $store.settings.screenshot.resolution) {
                    Text("Nativa (Retina)").tag(ResolutionScale.native)
                    Text("Reduzida (1×)").tag(ResolutionScale.points)
                }
                Toggle("Incluir cursor", isOn: $store.settings.screenshot.showsCursor)
            }
            Section("Depois de capturar") {
                Toggle("Copiar para a área de transferência", isOn: $store.settings.screenshot.copiesToClipboard)
                Toggle("Abrir no editor de marcações", isOn: $store.settings.screenshot.opensEditor)
                Toggle("Reproduzir som do obturador", isOn: $store.settings.screenshot.playsSound)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sobre

struct AboutTab: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("LibreScreen")
                    .font(.title.weight(.semibold))
                Text("Versão \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("A lightweight, open-source native screen recorder for macOS built with Swift and optimized for Apple Silicon.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .frame(maxWidth: 400)
            VStack(spacing: 4) {
                Text("Copyright © 2026 Renato Asterio")
                Text("PolyForm Noncommercial License 1.0.0 · uso não comercial, com créditos ao autor.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            Link(
                "github.com/renatoasterio/LibreScreen",
                destination: URL(string: "https://github.com/renatoasterio/LibreScreen") ?? URL(fileURLWithPath: "/")
            )
            .font(.callout)
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
