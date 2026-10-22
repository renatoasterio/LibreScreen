// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LibreScreen

struct FileNamingTests {
    @Test func nameContainsPrefixDateAndSummary() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = FileNaming.name(prefix: "Gravação", date: date, summary: "Finder")
        #expect(name.hasPrefix("Gravação "))
        #expect(name.hasSuffix(" – Finder"))
    }

    @Test func forbiddenCharactersAreRemoved() {
        #expect(FileNaming.sanitize("a/b:c*d?e\"f<g>h|i") == "abcdefghi")
    }

    @Test func leadingDotsAndWhitespaceAreStripped() {
        #expect(FileNaming.sanitize("  ..hidden  ") == "hidden")
    }

    @Test func longSummariesAreTruncated() {
        let long = String(repeating: "x", count: 120)
        #expect(FileNaming.sanitize(long).count == FileNaming.maximumSummaryLength)
    }

    @Test func emptySummaryOmitsSeparator() {
        let name = FileNaming.name(prefix: "Captura", date: Date(), summary: "   ")
        #expect(!name.contains("–"))
    }
}
