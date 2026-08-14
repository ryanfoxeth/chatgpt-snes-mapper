#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-"$HOME/.local/share/chatgpt-snes-mapper/ChatGPTSNESMapper.app"}"
CLI_PATH="${CLI_PATH:-"$HOME/.local/bin/chatgpt-snes-mapper"}"
BUNDLE_ID="io.github.ryanfoxeth.chatgpt-snes-mapper"

if [[ -z "${CODESIGN_IDENTITY+x}" ]] && command -v security >/dev/null 2>&1; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/\"Developer ID Application:/{print $2; exit}')"
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/\"Apple Development:/{print $2; exit}')"
  fi
fi
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

APP_MACOS_DIR="$APP_BUNDLE_PATH/Contents/MacOS"
APP_RESOURCES_DIR="$APP_BUNDLE_PATH/Contents/Resources"

mkdir -p "$APP_MACOS_DIR" "$APP_RESOURCES_DIR" "$(dirname "$CLI_PATH")"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE_PATH/Contents/Info.plist"

swiftc "$ROOT_DIR/SNESChatGPTMenuBar.swift" \
  -o "$APP_MACOS_DIR/ChatGPTSNESMapper"

swiftc "$ROOT_DIR/SNESChatGPTMapper.swift" \
  -o "$CLI_PATH"

if command -v codesign >/dev/null 2>&1; then
  if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - \
      --requirements "=designated => identifier \"$BUNDLE_ID\"" \
      "$APP_BUNDLE_PATH"
    echo "Warning: ad-hoc signing can make macOS forget Accessibility permission after a rebuild."
    echo "Set CODESIGN_IDENTITY to a stable Apple Development or Developer ID Application identity."
  else
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE_PATH"
  fi
fi

echo "Built app: $APP_BUNDLE_PATH"
echo "Built CLI: $CLI_PATH"
