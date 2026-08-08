#!/usr/bin/env bash
set -euo pipefail

LABEL="io.github.ryanfoxeth.chatgpt-snes-mapper"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
pkill -f "ChatGPTSNESMapper.app/Contents/MacOS/ChatGPTSNESMapper" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "Uninstalled LaunchAgent: $PLIST_PATH"
