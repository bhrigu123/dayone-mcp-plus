#!/bin/bash
# Removes the launch agent, the app, and its Full Disk Access entry.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/$APP_NAME.app" "$SUPPORT"
tccutil reset SystemPolicyAllFiles "$LABEL" >/dev/null 2>&1
echo "Uninstalled. Remove the \"dayone\" entry from your MCP client config too (e.g. claude mcp remove dayone -s user)."
