---
name: code-audit
description: Audits LibreScreen's Swift code for memory leaks, security weaknesses, permission misuse and Swift 6 concurrency mistakes, then reports findings by severity with file:line and a proposed fix (or applies the fixes with --fix). Use at the end of every milestone, before commits that touch Infrastructure, when reviewing a pull request, or whenever someone asks to check code quality, leaks, security or permissions.
---

# LibreScreen code audit

You are auditing a native macOS app (Swift 6 strict concurrency, SwiftUI, ScreenCaptureKit, AVFoundation, Vision, Core Image, AppKit panels). The architecture and the non-negotiable rules are in `CLAUDE.md` and `docs/ARCHITECTURE.md`; read both first if they are not already in context.

Arguments: `--changed` limits the audit to files changed since the last commit (default: whole project). `--fix` applies the fixes for High and Medium findings after reporting them. `--quick` skips the Clang static analyzer.

## Procedure

1. **Run the tooling.** From the repository root:
   ```bash
   .claude/skills/code-audit/scripts/audit.sh [--changed] [--quick]
   ```
   It runs SwiftFormat (lint mode), SwiftLint (strict), the Clang static analyzer, project-specific pattern scans, and a cross-check between `Info.plist`/entitlements and the APIs actually used. Every line it prints is a *candidate*, not a verdict.

2. **Review the code against the checklists.** Open each file in scope and apply the rule lists, choosing by layer:
   - `LibreScreen/Infrastructure/**` → `references/memory-rules.md`, `references/swift-concurrency-rules.md`, `references/permissions-rules.md`
   - `LibreScreen/Features/**` and `LibreScreen/App/**` → `references/memory-rules.md` (observers, panels, tasks, window ownership), `references/permissions-rules.md` (no requests outside `PermissionsService`), `references/swift-concurrency-rules.md` (`@MainActor` discipline)
   - `LibreScreen/Domain/**` → `references/swift-concurrency-rules.md` (`Sendable`), framework-free imports
   - `LibreScreen/Infrastructure/Storage/**`, anything writing files or the clipboard → `references/security-rules.md`
   Read the surrounding code before accepting a candidate: a `Task {}` in a SwiftUI `body` that never touches `self`, or a closure whose owner is guaranteed to outlive it (`// lifetime:` comment present), is not a finding.

3. **Classify.** Use the severity guide at the end of each reference file. In short: High = leaks in the recording path, permission requests outside the service or at launch, any networking/process spawning, data races on pipeline state, unsafe file writes; Medium = retain cycles in UI code, missing cancellation, unbounded buffers, missing validation of persisted values, privacy leaks in logs; Low = style, naming, missing doc comments on public types, lint warnings.

4. **Report.** Print a Markdown table sorted High → Medium → Low:

   | Severity | File:line | Rule | Problem | Proposed fix |

   followed by one line per tool section ("SwiftLint: 0 errors, 2 warnings", …) and a final verdict: **PASS** when there is no High finding and no lint/format error, otherwise **FAIL**. Keep each table cell to one sentence. Do not list the same root cause twice.

5. **Fix (only with `--fix`).** Apply High and Medium fixes in place, keeping the architecture rules (never move a permission request out of `PermissionsService`, never add a dependency). Then rebuild and test:
   ```bash
   xcodebuild -project LibreScreen.xcodeproj -scheme LibreScreen -configuration Debug -destination 'platform=macOS,arch=arm64' build
   xcodebuild -project LibreScreen.xcodeproj -scheme LibreScreen -destination 'platform=macOS,arch=arm64' test
   ```
   Re-run `audit.sh` and report what changed. Low findings are listed, not fixed, unless the fix is a one-liner.

6. **Dynamic verification** (when a Mac with a camera is available and the reviewer asks for it): launch the app, record one minute with the camera bubble and blur on, stop, then run `leaks <pid>` and `xcrun xctrace record --template Leaks --attach <pid> --time-limit 30s --output /tmp/leaks.trace`. Expected: zero leaks, memory footprint back to idle within a few seconds after stopping. The exact commands are in `references/memory-rules.md`.

## Guard rails

- Never weaken a rule to make a finding disappear; if a rule is wrong for this codebase, say so in the report and propose the change to `.swiftlint.yml` separately.
- Never request or change TCC permissions while auditing.
- The script is read-only; only `--fix` edits files, and only Swift sources.
