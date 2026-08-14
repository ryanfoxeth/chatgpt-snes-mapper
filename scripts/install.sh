#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="io.github.ryanfoxeth.chatgpt-snes-mapper"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-"$HOME/.local/share/chatgpt-snes-mapper/ChatGPTSNESMapper.app"}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

"$ROOT_DIR/scripts/build.sh"

mkdir -p "$(dirname "$PLIST_PATH")"
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>$APP_BUNDLE_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/chatgpt-snes-mapper.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/chatgpt-snes-mapper.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || open -g "$APP_BUNDLE_PATH"

echo "Installed LaunchAgent: $PLIST_PATH"
echo "If the menu bar shows SNES! or JOY!, enable the app in System Settings > Privacy & Security > Accessibility."
