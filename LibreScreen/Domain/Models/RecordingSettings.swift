// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

enum VideoCodec: String, Codable, CaseIterable, Sendable, Identifiable {
    case h264
    case hevc

    var id: String {
        rawValue
    }
}

enum VideoContainer: String, Codable, CaseIterable, Sendable, Identifiable {
    case mp4
    case mov

    var id: String {
        rawValue
    }

    var fileExtension: String {
        rawValue
    }
}

enum FrameRate: Int, Codable, CaseIterable, Sendable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int {
        rawValue
    }
}

enum VideoQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case standard
    case high
    case maximum

    var id: String {
        rawValue
    }

    /// Bits per pixel per frame used to derive the encoder bitrate.
    var bitsPerPixel: Double {
        switch self {
        case .standard: 0.06
        case .high: 0.11
        case .maximum: 0.20
        }
    }
}

/// Everything that shapes a recording file. Persisted as part of `AppSettings`.
struct RecordingSettings: Codable, Sendable, Equatable {
    static let allowedCountdowns = [0, 3, 5, 10]
    static let minimumBitrate = 2_000_000
    static let maximumBitrate = 80_000_000

    var codec: VideoCodec = .h264
    var container: VideoContainer = .mp4
    var frameRate: FrameRate = .fps30
    var quality: VideoQuality = .high
    var resolution: ResolutionScale = .native
    var showsCursor = true
    var countdownSeconds = 3
    var capturesSystemAudio = true
    var microphoneEnabled = false
    var microphoneDeviceID: String?
    /// `nil` means the default folder (`~/Movies/LibreScreen`).
    var outputDirectory: URL?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codec = try container.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .h264
        self.container = try container.decodeIfPresent(VideoContainer.self, forKey: .container) ?? .mp4
        frameRate = try container.decodeIfPresent(FrameRate.self, forKey: .frameRate) ?? .fps30
        quality = try container.decodeIfPresent(VideoQuality.self, forKey: .quality) ?? .high
        resolution = try container.decodeIfPresent(ResolutionScale.self, forKey: .resolution) ?? .native
        showsCursor = try container.decodeIfPresent(Bool.self, forKey: .showsCursor) ?? true
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? 3
        capturesSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .capturesSystemAudio) ?? true
        microphoneEnabled = try container.decodeIfPresent(Bool.self, forKey: .microphoneEnabled) ?? false
        microphoneDeviceID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        outputDirectory = try container.decodeIfPresent(URL.self, forKey: .outputDirectory)
    }

    /// Returns a copy with every value inside the supported range.
    func validated() -> RecordingSettings {
        var copy = self
        if !Self.allowedCountdowns.contains(copy.countdownSeconds) {
            copy.countdownSeconds = 3
        }
        return copy
    }

    /// Target average bitrate for the hardware encoder, derived from pixel count and frame rate.
    func bitrate(for pixelSize: CGSize) -> Int {
        let pixelsPerSecond = Double(pixelSize.width * pixelSize.height) * Double(frameRate.rawValue)
        let raw = Int(pixelsPerSecond * quality.bitsPerPixel)
        return min(max(raw, Self.minimumBitrate), Self.maximumBitrate)
    }
}
