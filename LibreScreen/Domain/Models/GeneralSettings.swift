// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

struct GeneralSettings: Codable, Sendable, Equatable {
    var showsInDock = true
    var showsMenuBarExtra = true
    var showsThumbnailPanel = true
    var revealsInFinderAfterRecording = false
    var playsSounds = true
    var hasCompletedOnboarding = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsInDock = try container.decodeIfPresent(Bool.self, forKey: .showsInDock) ?? true
        showsMenuBarExtra = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarExtra) ?? true
        showsThumbnailPanel = try container.decodeIfPresent(Bool.self, forKey: .showsThumbnailPanel) ?? true
        revealsInFinderAfterRecording = try container.decodeIfPresent(Bool.self, forKey: .revealsInFinderAfterRecording) ?? false
        playsSounds = try container.decodeIfPresent(Bool.self, forKey: .playsSounds) ?? true
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
}
