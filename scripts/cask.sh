#!/bin/bash
# Prints the Homebrew cask for a release. Usage: scripts/cask.sh <version> <sha256>
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh
VERSION="${1:?usage: scripts/cask.sh <version> <sha256>}"
SHA="${2:?usage: scripts/cask.sh <version> <sha256>}"

cat <<EOF
# typed: strict
# frozen_string_literal: true

cask "$EXECUTABLE" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$GITHUB_REPO/releases/download/v#{version}/$EXECUTABLE-#{version}.zip"
  name "$APP_NAME"
  desc "Touch ID-gated MCP server for Day One journals"
  homepage "https://github.com/$GITHUB_REPO"

  depends_on macos: ">= :ventura"

  app "$APP_NAME.app"
  binary "#{appdir}/$APP_NAME.app/Contents/MacOS/$EXECUTABLE"

  uninstall launchctl: "$AGENT_LABEL",
            script:    {
              executable:   "#{appdir}/$APP_NAME.app/Contents/MacOS/$EXECUTABLE",
              args:         ["unregister"],
              must_succeed: false,
            }

  zap trash: [
    "~/Library/Application Support/DayOneMCPPlus",
    "~/Library/Preferences/$LABEL.plist",
  ]

  caveats <<~EOS
    Open #{appdir}/$APP_NAME.app to finish setup (background helper, Full Disk Access,
    and connecting your AI app).
  EOS
end
EOF
