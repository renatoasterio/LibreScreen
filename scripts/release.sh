#!/bin/bash
# Builds a Release LibreScreen.app (ad-hoc signed) and zips it into dist/.
# Usage: scripts/release.sh [version]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:$PATH"

VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)}"
# Build products must stay outside the (possibly cloud-synced) repository folder: see CLAUDE.md.
DERIVED="${TMPDIR:-/tmp}/LibreScreen-release-DerivedData"

xcodegen generate >/dev/null
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO stops Xcode from adding the debug-only get-task-allow entitlement, which
# would let any local process attach to the shipped app.
xcodebuild -project LibreScreen.xcodeproj -scheme LibreScreen -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build

APP="$DERIVED/Build/Products/Release/LibreScreen.app"
mkdir -p dist
ZIP="LibreScreen-$VERSION.zip"
rm -f "dist/$ZIP" "dist/$ZIP.sha256"
# --norsrc keeps extended attributes out of the archive: with them, `unzip` writes ._* files into the bundle and the
# code signature no longer verifies.
ditto -c -k --norsrc --keepParent "$APP" "dist/$ZIP"
# Checksum taken inside dist/ so `shasum -a 256 -c` works next to a downloaded zip.
(cd dist && shasum -a 256 "$ZIP" | tee "$ZIP.sha256")
echo "Built dist/$ZIP"
echo "Note: the app is ad-hoc signed. A downloaded copy is allowed once in System Settings › Privacy & Security › Open Anyway."
