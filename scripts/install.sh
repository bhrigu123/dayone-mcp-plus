#!/bin/bash
# Builds "DayOne Unlocked.app" into ~/Applications and registers its background agent with launchd.
# Usage: scripts/install.sh [--unlock-minutes N]
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="local.dayone-unlocked.agent"
APP="$HOME/Applications/DayOne Unlocked.app"
BIN="$APP/Contents/MacOS/dayone-unlocked"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT="$HOME/Library/Application Support/DayOneUnlocked"
MINUTES=30
[[ "${1:-}" == "--unlock-minutes" && -n "${2:-}" ]] && MINUTES="$2"

echo "==> Building"
swift build -c release
BUILT="$(swift build -c release --show-bin-path)/dayone-unlocked"

# Re-signing changes the app's code hash, which voids its Full Disk Access grant,
# so only replace the app when the binary actually changed.
if [[ -f "$BIN" ]] && cmp -s "$BUILT" "$SUPPORT/.installed-binary"; then
  echo "==> App unchanged, keeping existing signature"
  CHANGED=0
else
  echo "==> Assembling $APP"
  mkdir -p "$APP/Contents/MacOS" "$SUPPORT"
  cp "$BUILT" "$BIN"
  cp "$BUILT" "$SUPPORT/.installed-binary"
  cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>DayOne Unlocked</string>
  <key>CFBundleDisplayName</key><string>DayOne Unlocked</string>
  <key>CFBundleExecutable</key><string>dayone-unlocked</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$("$BUILT" --version)</string>
  <key>CFBundleShortVersionString</key><string>$("$BUILT" --version)</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
  codesign --force --sign - --identifier "$LABEL" "$APP"
  CHANGED=1
fi

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
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

cat <<EOF

==> Installed. Remaining steps:

1. Give "DayOne Unlocked" Full Disk Access. If it doesn't have it yet, the app shows a dialog
   that opens the right pane (System Settings → Privacy & Security → Full Disk Access).
   If it isn't listed there, click + and choose: $APP
EOF
if [[ "$CHANGED" == 1 ]]; then
  echo "   (The app was rebuilt; if it was already listed, switch it off and on again.)"
fi
cat <<EOF
   If Settings doesn't offer "Quit & Reopen", restart the agent:
     launchctl kickstart -k gui/$(id -u)/$LABEL

2. Add the MCP server to your client, e.g. Claude Code:
     claude mcp add dayone -s user -- "$BIN" mcp

   or in a JSON config (Claude Desktop and others):
     "dayone": { "command": "$BIN", "args": ["mcp"] }
EOF
