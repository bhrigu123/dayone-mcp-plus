#!/bin/bash
# Builds and signs "Day One MCP Plus.app" into ~/Applications, turns on its background helper,
# and opens its setup window. (End users just open the app; this is the from-source path.)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

APP="$HOME/Applications/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$EXECUTABLE"
DOMAIN="gui/$(id -u)"

# Remove earlier installs that used a launch agent plist in ~/Library/LaunchAgents.
for OLD in local.dayone-unlocked.agent local.dayone-mcp-plus.agent com.bhrigu.dayone-mcp-plus; do
  if [[ -e "$HOME/Library/LaunchAgents/$OLD.plist" ]]; then
    echo "==> Removing previous install ($OLD)"
    launchctl bootout "$DOMAIN/$OLD" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$OLD.plist"
    if [[ "$OLD" == local.* ]]; then
      tccutil reset SystemPolicyAllFiles "$OLD" >/dev/null 2>&1 || true
    fi
  fi
done
rm -rf "$HOME/Applications/DayOne Unlocked.app" "$HOME/Library/Application Support/DayOneUnlocked"

mkdir -p "$HOME/Applications"
scripts/build-app.sh "$HOME/Applications"

echo "==> Turning on the background helper"
"$BIN" register
open "$APP"
echo "==> Installed. Finish setup in the window that just opened."
