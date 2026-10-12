#!/bin/bash
# Builds and signs "Day One MCP Plus.app" into the given directory.
#
# Signing identity, in order: $SIGN_IDENTITY, the first "Developer ID Application" certificate,
# the first "Apple Development" certificate, else ad-hoc. A real certificate gives the app a
# stable identity, so its Full Disk Access grant survives rebuilds.
# Set REQUIRE_DEVELOPER_ID=1 to fail unless a Developer ID certificate is used (for releases).
#
# Usage: scripts/build-app.sh <output-dir>
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh
OUT="${1:?usage: scripts/build-app.sh <output-dir>}"
APP="$OUT/$APP_NAME.app"

echo "==> Building"
swift build -c release
BUILT="$(swift build -c release --show-bin-path)/$EXECUTABLE"
VERSION="$("$BUILT" --version)"

first_identity() {
  security find-identity -v -p codesigning | awk -v kind="$1" 'index($0, "\"" kind) { sub(/^[^"]*"/, ""); sub(/"$/, ""); print; exit }'
}
IDENTITY="${SIGN_IDENTITY:-}"
[[ -z "$IDENTITY" ]] && IDENTITY="$(first_identity "Developer ID Application")"
if [[ "${REQUIRE_DEVELOPER_ID:-0}" == 1 && "$IDENTITY" != "Developer ID Application"* ]]; then
  echo "error: no Developer ID Application certificate found (needed to share the app)." >&2
  echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application." >&2
  exit 1
fi
[[ -z "$IDENTITY" ]] && IDENTITY="$(first_identity "Apple Development")"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILT" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

if [[ -n "$IDENTITY" ]]; then
  echo "==> Signing with: $IDENTITY"
  FLAGS=(--options runtime)  # hardened runtime, required for notarization
  [[ "$IDENTITY" == "Developer ID Application"* ]] && FLAGS+=(--timestamp)
  codesign --force "${FLAGS[@]}" --sign "$IDENTITY" --identifier "$LABEL" "$APP"
else
  echo "==> No signing certificate found; signing ad-hoc (Full Disk Access resets on every rebuild)"
  codesign --force --sign - --identifier "$LABEL" "$APP"
fi
codesign --verify --strict "$APP"
