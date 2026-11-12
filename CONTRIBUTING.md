# Contributing to LibreScreen

Thanks for helping! This document explains the ways to take part, how the project is organised and what a pull
request needs. Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** with the [bug report form](https://github.com/renatoasterio/LibreScreen/issues/new/choose). Your
  macOS version, Mac model and display setup make it much easier to reproduce.
- **Propose an idea** in [Discussions › Ideas](https://github.com/renatoasterio/LibreScreen/discussions/categories/ideas)
  before writing a large change, so the design can be agreed first.
- **Translate the app** (see [Adding a language](#adding-a-language)).
- **Improve the docs**, including `README.pt-BR.md`, which mirrors `README.md`.
- **Send code.** Issues labelled
  [`good first issue`](https://github.com/renatoasterio/LibreScreen/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  and [`help wanted`](https://github.com/renatoasterio/LibreScreen/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)
  are the best places to start.

## Setup

You need macOS 15 or later, an Apple Silicon Mac and Xcode 26.5 or later.

```bash
make tools      # one-time: xcodegen, swiftlint and swiftformat through Homebrew
make run        # Debug build and launch
make test       # unit tests
make help       # every target
```

`project.yml` is the source of truth for the Xcode project. If you add, move or
rename files outside Xcode, run `make generate` and commit the regenerated
`LibreScreen.xcodeproj`.

Build products stay outside the repository: the Makefile uses a DerivedData
folder under `~/Library/Developer/Xcode/DerivedData`. Do not pass a
`-derivedDataPath` inside the checkout.

## Ground rules

- Read `docs/ARCHITECTURE.md` first. Code lives in one of three layers
  (Domain, Infrastructure, Features/Presentation) and dependencies only point
  downwards. `Domain` never imports AppKit, SwiftUI, AVFoundation,
  ScreenCaptureKit, Vision or Core Image.
- Swift 6 language mode with strict concurrency. No `try!`, `as!` or forced
  unwraps outside tests. Errors are typed (`LibreScreenError`) and surfaced to
  the user.
- Every escaping closure captures `self` weakly unless its lifetime is clearly
  bounded, in which case add a `// lifetime:` comment explaining why.
- Permissions are requested only inside `PermissionsService` and only in
  response to a user action.
- No networking, telemetry, process spawning or dynamic code loading. These are
  the guarantees in `SECURITY.md`, and the audit fails when they are broken.
- All user-facing text goes through the String Catalog
  (`LibreScreen/Resources/Localizable.xcstrings`) with Portuguese (Brazil) as
  the source language and an English translation.
- Public types and non-obvious decisions get a short doc comment. Comments
  explain *why*, not *what*.

`CLAUDE.md` holds the same rules in the form AI coding agents read. If you use
one, point it at that file.

## Checking your work

```bash
make format     # apply SwiftFormat
make lint       # SwiftFormat in lint mode + SwiftLint strict
make test       # unit tests
make audit      # lint, static analyzer and the project's safety scans
make smoke      # headless recording with a synthetic webcam, then screenshots
make snapshot   # renders every screen to PNG, in light and dark
```

`make smoke` and `make snapshot` use Debug-only launch arguments and need the
Debug build to have the Screen Recording permission. They let you verify the
capture path and the UI from a terminal.

## Before you open a pull request

1. `make lint` reports nothing and `make test` passes.
2. `make audit` reports no high-severity findings (or your PR explains why a
   finding is a false positive).
3. New logic in `Domain`, `UseCases` or ViewModels comes with Swift Testing
   tests using the fakes in `LibreScreenTests/Fakes`.
4. UI changes include before and after screenshots in light and dark
   appearance (`make snapshot` produces them).
5. The PR description says what changed, why, and how you verified it
   manually (which display, camera, permissions state).

## Adding a language

1. Open `LibreScreen/Resources/Localizable.xcstrings` in Xcode and add the
   language with the **+** button. Portuguese (Brazil) is the source language,
   and the English column is a good reference.
2. Translate every string. Keep placeholders such as `%@` and `%lld` intact.
3. Add the language code to `CFBundleLocalizations` in
   `LibreScreen/Resources/Info.plist`.
4. Run the app in the new language and check that nothing is truncated:
   `open -a LibreScreen --args -AppleLanguages '(fr)'`.

## Commit messages

Use the imperative mood and keep the first line under 72 characters, for
example `Add region selection overlay for multi-monitor setups`.

## License

By contributing you agree that your contribution is licensed under the
PolyForm Noncommercial License 1.0.0 that covers the project.
