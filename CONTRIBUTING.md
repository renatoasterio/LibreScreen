# Contributing to LibreScreen

Thanks for helping! This document explains how the project is organised and what a pull request needs.

## Setup

```bash
brew install xcodegen swiftlint swiftformat
xcodegen generate
open LibreScreen.xcodeproj
```

`project.yml` is the source of truth for the Xcode project. If you add, move or
rename files outside Xcode, run `xcodegen generate` again and commit the
regenerated `LibreScreen.xcodeproj`.

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
- All user-facing text goes through the String Catalog
  (`LibreScreen/Resources/Localizable.xcstrings`) with Portuguese (Brazil) as
  the source language and an English translation.
- Public types and non-obvious decisions get a short doc comment. Comments
  explain *why*, not *what*.

## Before you open a pull request

1. `swiftformat .` and `swiftlint --strict` report nothing.
2. `xcodebuild -scheme LibreScreen test` passes.
3. `.claude/skills/code-audit/scripts/audit.sh` reports no high-severity
   findings (or your PR explains why a finding is a false positive).
4. New logic in `Domain`, `UseCases` or ViewModels comes with Swift Testing
   tests using the fakes in `LibreScreenTests/Fakes`.
5. The PR description says what changed, why, and how you verified it
   manually (which display, camera, permissions state).

## Commit messages

Use the imperative mood and keep the first line under 72 characters, for
example `Add region selection overlay for multi-monitor setups`.

## License

By contributing you agree that your contribution is licensed under the
PolyForm Noncommercial License 1.0.0 that covers the project.
