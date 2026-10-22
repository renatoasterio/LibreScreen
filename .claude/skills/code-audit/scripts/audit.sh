#!/bin/bash
# LibreScreen code audit: lint, format, static analysis and project-specific safety scans.
# Read-only. Exit code is non-zero when SwiftLint reports errors or SwiftFormat finds violations.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT" || exit 2
export PATH="/opt/homebrew/bin:$PATH"

MODE="all"
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --changed) MODE="changed" ;;
    --quick) QUICK=1 ;;
  esac
done

if [[ "$MODE" == "changed" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FILES=$( { git diff --name-only HEAD -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift'; } | sort -u | grep -E '^(LibreScreen|LibreScreenTests)/' )
else
  FILES=$(find LibreScreen LibreScreenTests -name '*.swift' | sort)
fi
if [[ -z "$FILES" ]]; then
  echo "No Swift files in scope."; exit 0
fi
APP_FILES=$(echo "$FILES" | grep -E '^LibreScreen/' || true)
STATUS=0

section() { printf '\n== %s ==\n' "$1"; }

section "Scope ($MODE): $(echo "$FILES" | wc -l | tr -d ' ') files"

section "SwiftFormat (lint mode)"
if command -v swiftformat >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  if ! swiftformat --lint --quiet $FILES; then STATUS=1; fi
else
  echo "swiftformat not installed (brew install swiftformat)"
fi

section "SwiftLint (strict)"
if command -v swiftlint >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  if ! swiftlint lint --strict --quiet --config .swiftlint.yml $FILES; then STATUS=1; fi
else
  echo "swiftlint not installed (brew install swiftlint)"
fi

if [[ "$QUICK" -eq 0 ]]; then
  section "Clang static analyzer"
  xcodebuild -project LibreScreen.xcodeproj -scheme LibreScreen -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -quiet analyze 2>&1 \
    | grep -E 'warning:|error:' | grep -v appintentsmetadataprocessor | sed "s|$ROOT/||" | sort -u || true
fi

scan() {
  # scan "<label>" "<perl regex>" [files...]  — Perl so that \b, \s and look-behinds work on macOS.
  local label="$1" regex="$2"; shift 2
  local hits
  hits=$(perl -ne 'BEGIN { $re = shift } next if /^\s*\/\//; print "$ARGV:$.: $_" if /$re/; close ARGV if eof' "$regex" "$@" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    printf '\n-- %s --\n%s\n' "$label" "$hits"
  fi
}

section "Pattern scan (candidates for manual review)"
# shellcheck disable=SC2086
INFRA=$(echo "$APP_FILES" | grep -E '^LibreScreen/Infrastructure/' || true)
# shellcheck disable=SC2086
NON_PERMISSIONS=$(echo "$APP_FILES" | grep -v 'Infrastructure/Permissions/' || true)
# shellcheck disable=SC2086
NON_STORAGE=$(echo "$APP_FILES" | grep -v 'Infrastructure/Storage/' | grep -v 'App/AppContainer.swift' || true)

[[ -n "$APP_FILES" ]] && scan "Forced try / cast / unwrap" '(\btry!|\bas!|[A-Za-z0-9_)\]]!\s*[.;,)]|[A-Za-z0-9_)\]]!$)' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Escaping closures that mention self on the same line (check for [weak self])" '(Task\s*(\(|\{)|\.async\s*\{|setEventHandler\s*\{|\.sink\s*\{|addObserver\(forName)[^\n]*\bself\b' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Timer.scheduledTimer (retains target/closure)" 'Timer\.scheduledTimer' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "unowned captures" '\bunowned\b' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Blocking primitives" '(DispatchSemaphore|\.wait\(\)|DispatchGroup\(\)|(?<![.\w])(usleep|sleep)\()' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Networking / telemetry" '(URLSession|NWConnection|NWListener|CFSocket|import Network|Analytics|Telemetry)' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Process spawning / dynamic loading" '((?<![.\w])Process\(|NSTask|posix_spawn|dlopen|dlsym|Bundle\([^)]*\)\.load)' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "print / NSLog" '^\s*(print|debugPrint|NSLog)\(' $APP_FILES
[[ -n "$NON_PERMISSIONS" ]] && scan "Permission requests outside PermissionsService" '(AVCaptureDevice\.requestAccess|CGRequestScreenCaptureAccess)' $NON_PERMISSIONS
[[ -n "$NON_STORAGE" ]] && scan "UserDefaults outside Storage" 'UserDefaults\.' $NON_STORAGE
[[ -n "$INFRA" ]] && scan "DispatchQueue.main in Infrastructure" 'DispatchQueue\.main' $INFRA
[[ -n "$APP_FILES" ]] && scan "Stored sample buffers (release promptly)" '(var|let)\s+\w+\s*:\s*(CMSampleBuffer|\[CMSampleBuffer\])' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Logger interpolation without privacy annotation for paths/titles" 'Log\.[a-z]+\.(info|debug|error|warning|notice)\([^)]*\\\((url|path|title|name)[^)]*\)' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Observers added (verify removal / token lifetime)" 'addObserver\(' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Global/local event monitors (verify removeMonitor)" 'NSEvent\.add(Global|Local)MonitorForEvents' $APP_FILES
[[ -n "$APP_FILES" ]] && scan "Domain importing frameworks" '^import (AppKit|SwiftUI|AVFoundation|ScreenCaptureKit|Vision|CoreImage)' $(echo "$APP_FILES" | grep '^LibreScreen/Domain/' || true)

section "Info.plist / entitlements vs API usage"
PLIST="LibreScreen/Resources/Info.plist"
ENT="LibreScreen/Resources/LibreScreen.entitlements"
uses_camera=$(grep -lE 'AVCaptureDevice|AVCaptureSession' $APP_FILES 2>/dev/null | wc -l | tr -d ' ')
uses_mic=$(grep -lE 'mediaType: \.audio|AVCaptureAudioDataOutput|for: \.audio' $APP_FILES 2>/dev/null | wc -l | tr -d ' ')
check_key() { if grep -q "<key>$1</key>" "$2"; then echo "ok   $1"; else echo "MISSING $1 in $2"; STATUS=1; fi; }
[[ "$uses_camera" -gt 0 ]] && check_key NSCameraUsageDescription "$PLIST"
[[ "$uses_mic" -gt 0 ]] && check_key NSMicrophoneUsageDescription "$PLIST"
check_key com.apple.security.device.camera "$ENT"
check_key com.apple.security.device.audio-input "$ENT"
if grep -A1 'com.apple.security.app-sandbox' "$ENT" | grep -q '<true/>'; then
  echo "NOTE App Sandbox is enabled; verify file access paths."
else
  echo "ok   App Sandbox disabled (direct distribution)"
fi
if grep -qE 'com.apple.security.network' "$ENT"; then echo "FAIL network entitlement present"; STATUS=1; else echo "ok   no network entitlements"; fi

section "Result"
if [[ "$STATUS" -eq 0 ]]; then echo "Tooling passed. Review the candidates above manually."; else echo "Tooling reported errors (see above)."; fi
exit "$STATUS"
