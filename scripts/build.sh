#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-"$HOME/.local/share/chatgpt-snes-mapper/ChatGPTSNESMapper.app"}"
CLI_PATH="${CLI_PATH:-"$HOME/.local/bin/chatgpt-snes-mapper"}"
BUNDLE_ID="io.github.ryanfoxeth.chatgpt-snes-mapper"

APP_MACOS_DIR="$APP_BUNDLE_PATH/Contents/MacOS"
APP_RESOURCES_DIR="$APP_BUNDLE_PATH/Contents/Resources"

mkdir -p "$APP_MACOS_DIR" "$APP_RESOURCES_DIR" "$(dirname "$CLI_PATH")"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE_PATH/Contents/Info.plist"

swiftc "$ROOT_DIR/SNESChatGPTMenuBar.swift" \
  -o "$APP_MACOS_DIR/ChatGPTSNESMapper"

swiftc "$ROOT_DIR/SNESChatGPTMapper.swift" \
  -o "$CLI_PATH"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP_BUNDLE_PATH"
fi

echo "Built app: $APP_BUNDLE_PATH"
echo "Built CLI: $CLI_PATH"
