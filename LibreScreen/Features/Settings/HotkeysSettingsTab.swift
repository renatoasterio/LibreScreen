// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// One recorder per global action. Registration happens live through `HotkeyCoordinator`.
struct HotkeysSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var store = container.settings
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(Self.title(for: action)) {
                        HotkeyRecorder(hotkey: binding(for: action, store: store))
                    }
                }
            } header: {
                Text("Atalhos globais")
            } footer: {
                Text("Funcionam em qualquer app. Use ⌃, ⌥ ou ⌘ para não conflitar com a digitação.")
            }
            if !container.hotkeys.failedActions.isEmpty {
                Section {
                    Label(failureMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Button("Restaurar padrões") {
                    store.settings.hotkeys = HotkeySettings()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var failureMessage: String {
        let names = container.hotkeys.failedActions.map(Self.title(for:)).joined(separator: ", ")
        return String(localized: "Não foi possível registrar: \(names). Outro app já usa essa combinação.")
    }

    private func binding(for action: HotkeyAction, store: SettingsStore) -> Binding<Hotkey?> {
        Binding(
            get: { store.settings.hotkeys[action] },
            set: { store.settings.hotkeys[action] = $0 }
        )
    }

    static func title(for action: HotkeyAction) -> String {
        switch action {
        case .recordDisplay: String(localized: "Gravar tela inteira")
        case .recordWindow: String(localized: "Gravar janela")
        case .recordRegion: String(localized: "Gravar área")
        case .screenshotDisplay: String(localized: "Capturar tela inteira")
        case .screenshotWindow: String(localized: "Capturar janela")
        case .screenshotRegion: String(localized: "Capturar área")
        case .stopRecording: String(localized: "Parar gravação")
        case .pauseResumeRecording: String(localized: "Pausar ou retomar")
        case .toggleHub: String(localized: "Mostrar ou ocultar o LibreScreen")
        }
    }
}
