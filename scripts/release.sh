#!/bin/bash
# Builds a Developer ID–signed, notarized, stapled release zip in dist/ for sharing.
#
# One-time setup: create a "Developer ID Application" certificate (Xcode → Settings → Accounts →
# Manage Certificates), then store notarization credentials in the keychain:
#   xcrun notarytool store-credentials dayone-mcp-plus --apple-id <you@example.com> --team-id <TEAMID>
# (it asks for an app-specific password from account.apple.com).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh
PROFILE="${NOTARY_PROFILE:-dayone-mcp-plus}"

rm -rf dist && mkdir -p dist
REQUIRE_DEVELOPER_ID=1 scripts/build-app.sh dist
APP="dist/$APP_NAME.app"
VERSION="$("$APP/Contents/MacOS/$EXECUTABLE" --version)"
ZIP="dist/$EXECUTABLE-$VERSION.zip"

echo "==> Notarizing (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

# Re-zip so the stapled ticket ships inside the archive.
rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
echo "==> Release ready: $ZIP"
