// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Every failure the user can hit, with a localized description and a recovery suggestion.
enum LibreScreenError: Error, Equatable, Sendable {
    case permissionDenied(Permission)
    case noDisplaysAvailable
    case sourceUnavailable
    case captureFailed(reason: String)
    case writerFailed(reason: String)
    case cameraUnavailable
    case microphoneUnavailable
    case outputDirectoryUnavailable(path: String)
    case exportFailed(reason: String)
    case hotkeyRegistrationFailed(HotkeyAction)
    case alreadyRecording
    case cancelled
}

extension LibreScreenError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .permissionDenied(permission):
            switch permission {
            case .screenRecording: String(localized: "Sem permissão para gravar a tela.")
            case .camera: String(localized: "Sem permissão para usar a câmera.")
            case .microphone: String(localized: "Sem permissão para usar o microfone.")
            }
        case .noDisplaysAvailable: String(localized: "Nenhum monitor disponível para captura.")
        case .sourceUnavailable: String(localized: "A janela ou o monitor escolhido não está mais disponível.")
        case let .captureFailed(reason): String(localized: "A captura falhou: \(reason)")
        case let .writerFailed(reason): String(localized: "Não foi possível salvar o vídeo: \(reason)")
        case .cameraUnavailable: String(localized: "A câmera não está disponível.")
        case .microphoneUnavailable: String(localized: "O microfone não está disponível.")
        case let .outputDirectoryUnavailable(path): String(localized: "Não foi possível acessar a pasta de saída \(path).")
        case let .exportFailed(reason): String(localized: "A exportação falhou: \(reason)")
        case .hotkeyRegistrationFailed: String(localized: "Não foi possível registrar o atalho global.")
        case .alreadyRecording: String(localized: "Já existe uma gravação em andamento.")
        case .cancelled: String(localized: "Operação cancelada.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            String(localized: "Abra Ajustes do Sistema › Privacidade e Segurança e permita o acesso para o LibreScreen.")
        case .sourceUnavailable:
            String(localized: "Escolha outra janela ou monitor e tente novamente.")
        case .outputDirectoryUnavailable:
            String(localized: "Escolha outra pasta em Configurações › Geral.")
        case .cameraUnavailable, .microphoneUnavailable:
            String(localized: "Verifique se o dispositivo está conectado e não está em uso por outro app.")
        case .hotkeyRegistrationFailed:
            String(localized: "Escolha outra combinação de teclas em Configurações › Atalhos.")
        default:
            nil
        }
    }
}
