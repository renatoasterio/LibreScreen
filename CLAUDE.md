# LibreScreen — working agreement for humans and AI agents

LibreScreen is a native macOS screen recorder (Swift 6, SwiftUI, ScreenCaptureKit, AVFoundation, Vision).
Minimum macOS 15, Apple Silicon only, no App Sandbox, hardened runtime on, zero third-party runtime dependencies.

## Commands

```bash
make run          # Debug build + launch (make build / make test / make lint / make format / make audit)
make release      # Release build, ad-hoc signed, zipped into dist/ (make install copies it to /Applications)
make smoke        # headless pipeline check: -autorecord with a synthetic webcam, then -autoscreenshot
make generate     # regenerate LibreScreen.xcodeproj from project.yml (source of truth) after adding files
```

The Makefile wraps `xcodegen`, `xcodebuild`, `swiftformat`, `swiftlint` and `.claude/skills/code-audit/scripts/audit.sh`.

Run `/code-audit` (project skill) at the end of every milestone and before any commit that touches `Infrastructure`.

Build products must stay outside the repository (the Makefile uses `~/Library/Developer/Xcode/DerivedData/LibreScreen-make`).
A checkout inside a File-Provider-synced folder (iCloud/Documents) gets `com.apple.FinderInfo` stamped on new bundles and
`codesign` fails with "resource fork, Finder information, or similar detritus not allowed". Never pass `-derivedDataPath`
pointing inside the repository.

## Architecture (see docs/ARCHITECTURE.md)

- `LibreScreen/Domain` — pure models, protocols and use cases. Never imports AppKit, SwiftUI, AVFoundation, ScreenCaptureKit, Vision or Core Image.
- `LibreScreen/Infrastructure` — concrete services, one folder per framework. The only layer that touches capture SDKs.
- `LibreScreen/Features` — SwiftUI views + `@MainActor @Observable` ViewModels, one folder per feature. ViewModels depend on Domain protocols only; AppKit window controllers for floating panels live here too.
- `LibreScreen/Shared` — reusable components (`GlassSurface`, `GlassButtonStyle`, …) and extensions.
- `LibreScreen/App` — entry point, `AppDelegate`, `AppContainer` (composition root), `Log`.
- Dependencies point downwards only: Features → Infrastructure → Domain. Never the other way.

## Non-negotiable rules

1. **Permissions**: only `Infrastructure/Permissions/PermissionsService.swift` may call `CGRequestScreenCaptureAccess` or `AVCaptureDevice.requestAccess`, and only in response to a user action. Nothing is requested at launch.
2. **No networking, no telemetry, no process spawning, no dynamic code loading.**
3. **Memory**: `[weak self]` in escaping closures (or a `// lifetime:` comment explaining why not), `weak` delegates, `DispatchSourceTimer` cancelled in `deinit`, `CVPixelBufferPool` reuse, `autoreleasepool` in frame loops, `CMSampleBuffer`s released promptly.
4. **Concurrency**: Swift 6 strict. UI on `@MainActor`; capture callbacks on their own serial queues; frames wrapped in documented `@unchecked Sendable` structs; no `DispatchQueue.main` in `Infrastructure`; no semaphores on the main thread.
5. **Errors**: typed `LibreScreenError`, never `try!`, `as!` or `!` on optionals outside tests. Every failure the user can hit reaches an alert with a recovery suggestion.
6. **Logging**: `Log.<category>` (`os.Logger`), `privacy: .private` for paths, window titles and device names. No `print`.
7. **Localization**: every user-facing string goes through SwiftUI `Text`/`String(localized:)` with the Portuguese (Brazil) text as the key and an English translation in `Resources/Localizable.xcstrings`.
8. **UI**: Apple HIG. Liquid Glass through `GlassSurface`/`GlassButtonStyle` (which fall back on macOS 15). System fonts, SF Symbols, standard spacing from `DesignTokens`. Accessibility labels on every control.
9. **Files**: atomic writes, user-chosen folders only, sanitised names from `FileNaming`, temp files under `FileManager.default.temporaryDirectory` and deleted afterwards.
10. **Tests**: Swift Testing for Domain, UseCases and ViewModels using `LibreScreenTests/Fakes`. Infrastructure is verified manually (see docs/ARCHITECTURE.md → Verification).

## Style

SwiftFormat and SwiftLint configs are authoritative (`.swiftformat`, `.swiftlint.yml`). Doc comments explain *why*. Keep files under 500 lines and functions under 60. Code, comments and docs are written in English; the UI source language is Portuguese (Brazil).
