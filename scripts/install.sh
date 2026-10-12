#!/bin/bash
# Builds and signs "Day One MCP Plus.app" into ~/Applications and registers its background agent.
# Usage: scripts/install.sh [--unlock-minutes N]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

APP="$HOME/Applications/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$EXECUTABLE"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MINUTES=30
[[ "${1:-}" == "--unlock-minutes" && -n "${2:-}" ]] && MINUTES="$2"
DOMAIN="gui/$(id -u)"

# Remove installs from before the rename and the move to a signed bundle identifier.
for OLD in local.dayone-unlocked.agent local.dayone-mcp-plus.agent; do
  if [[ -e "$HOME/Library/LaunchAgents/$OLD.plist" ]]; then
    echo "==> Removing previous install ($OLD)"
    launchctl bootout "$DOMAIN/$OLD" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$OLD.plist"
    tccutil reset SystemPolicyAllFiles "$OLD" >/dev/null 2>&1 || true
  fi
done
rm -rf "$HOME/Applications/DayOne Unlocked.app" "$HOME/Library/Application Support/DayOneUnlocked"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications"
scripts/build-app.sh "$HOME/Applications"

echo "==> Registering launch agent"
mkdir -p "$SUPPORT" "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
    <string>agent</string>
    <string>--unlock-minutes</string>
    <string>$MINUTES</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>StandardErrorPath</key><string>$SUPPORT/agent.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "$DOMAIN" "$PLIST"

cat <<EOF

==> Installed.

If $APP_NAME doesn't have Full Disk Access yet, it shows a dialog that opens the right
Settings pane. If Settings doesn't offer "Quit & Reopen", restart it with:
  launchctl kickstart -k $DOMAIN/$LABEL

Add it to your MCP client, e.g. Claude Code:
  claude mcp add dayone -s user -- "$BIN" mcp
or in a JSON config (Claude Desktop and others):
  "dayone": { "command": "$BIN", "args": ["mcp"] }
EOF
