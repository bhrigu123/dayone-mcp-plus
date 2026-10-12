#!/bin/bash
# Turns off the background helper and removes the app, its data, and its Full Disk Access entry.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

APP="$HOME/Applications/$APP_NAME.app"
if [[ -x "$APP/Contents/MacOS/$EXECUTABLE" ]]; then
  "$APP/Contents/MacOS/$EXECUTABLE" unregister
fi
rm -rf "$APP" "$SUPPORT"
tccutil reset SystemPolicyAllFiles "$LABEL" >/dev/null 2>&1
echo "Uninstalled. Remove the \"dayone\" entry from your MCP client config too (e.g. claude mcp remove dayone -s user)."
