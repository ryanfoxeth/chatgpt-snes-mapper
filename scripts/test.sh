#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chatgpt-controller-mapper-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT

APP_PATH="$TEST_DIR/ChatGPT Controller Mapper.app"
CLI_PATH="$TEST_DIR/chatgpt-snes-mapper"

APP_BUNDLE_PATH="$APP_PATH" \
CLI_PATH="$CLI_PATH" \
CODESIGN_IDENTITY=- \
"$ROOT_DIR/scripts/build.sh" >/dev/null

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_PATH"

MENU_MAPPINGS="$("$APP_PATH/Contents/MacOS/ChatGPTSNESMapper" --print-default-mappings)"
CLI_MAPPINGS="$("$CLI_PATH" --print-default-mappings)"
CLI_HELP="$("$CLI_PATH" --help)"

assert_contains() {
  local output="$1"
  local expected="$2"
  if ! grep -Fqx "$expected" <<<"$output"; then
    echo "Missing expected mapping: $expected" >&2
    exit 1
  fi
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  if grep -Fqx "$unexpected" <<<"$output"; then
    echo "Unexpected mapping remains: $unexpected" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq "$expected" "$file"; then
    echo "Missing expected implementation in $file: $expected" >&2
    exit 1
  fi
}

# Menu app: preserve every original SNES default.
assert_contains "$MENU_MAPPINGS" "SNES.a.A=holdDictation"
assert_contains "$MENU_MAPPINGS" "SNES.b.B=send"
assert_contains "$MENU_MAPPINGS" "SNES.x.X=toggleVoiceChat"
assert_contains "$MENU_MAPPINGS" "SNES.y.Y=clearInput"
assert_contains "$MENU_MAPPINGS" "SNES.l.L=toggleVoiceMic"
assert_contains "$MENU_MAPPINGS" "SNES.r.R=toggleVoiceMic"
assert_contains "$MENU_MAPPINGS" "SNES.zl.ZL=newChat"
assert_contains "$MENU_MAPPINGS" "SNES.zr.ZR=lockUnlock"
assert_contains "$MENU_MAPPINGS" "SNES.select.Select=focusChatGPT"
assert_contains "$MENU_MAPPINGS" "SNES.start.Start=focusChatGPT"
assert_contains "$MENU_MAPPINGS" "SNES.dpadUp.D-pad Up=previousChat"
assert_contains "$MENU_MAPPINGS" "SNES.dpadDown.D-pad Down=nextChat"
assert_contains "$MENU_MAPPINGS" "SNES.dpadLeft.D-pad Left=toggleSidebar"
assert_contains "$MENU_MAPPINGS" "SNES.dpadRight.D-pad Right=toggleSidePanel"

# Menu app: Joy-Con-only overrides plus unchanged controls.
assert_contains "$MENU_MAPPINGS" "JOY.a.A=holdDictation"
assert_contains "$MENU_MAPPINGS" "JOY.b.B=send"
assert_contains "$MENU_MAPPINGS" "JOY.x.X=toggleVoiceChat"
assert_contains "$MENU_MAPPINGS" "JOY.y.Y=clearInput"
assert_contains "$MENU_MAPPINGS" "JOY.l.SL=toggleVoiceMic"
assert_contains "$MENU_MAPPINGS" "JOY.r.SR=expandBrowserContentPanel"
assert_contains "$MENU_MAPPINGS" "JOY.zl.R=toggleVoiceMic"
assert_contains "$MENU_MAPPINGS" "JOY.zr.ZR=lockUnlock"
assert_contains "$MENU_MAPPINGS" "JOY.start.+=newChat"
assert_contains "$MENU_MAPPINGS" "JOY.select.Home=focusChatGPT"
assert_contains "$MENU_MAPPINGS" "JOY.dpadUp.Stick Up=previousChat"
assert_contains "$MENU_MAPPINGS" "JOY.dpadDown.Stick Down=nextChat"
assert_contains "$MENU_MAPPINGS" "JOY.dpadLeft.Stick Left=toggleSidebar"
assert_contains "$MENU_MAPPINGS" "JOY.dpadRight.Stick Right=toggleSidePanel"

# CLI: preserve the complete SNES profile.
assert_contains "$CLI_MAPPINGS" "8215.button.1=send"
assert_contains "$CLI_MAPPINGS" "8215.button.2=hold dictation"
assert_contains "$CLI_MAPPINGS" "8215.button.3=clear input"
assert_contains "$CLI_MAPPINGS" "8215.button.4=toggle Voice Chat"
assert_contains "$CLI_MAPPINGS" "8215.button.5=toggle Voice Chat microphone"
assert_contains "$CLI_MAPPINGS" "8215.button.6=toggle Voice Chat microphone"
assert_contains "$CLI_MAPPINGS" "8215.button.7=new chat"
assert_contains "$CLI_MAPPINGS" "8215.button.9=focus ChatGPT"
assert_contains "$CLI_MAPPINGS" "8215.button.10=focus ChatGPT"
assert_contains "$CLI_MAPPINGS" "8215.button.16=lock/unlock mapper"
assert_contains "$CLI_MAPPINGS" "8215.hat.0=previous chat"
assert_contains "$CLI_MAPPINGS" "8215.hat.2=toggle side panel"
assert_contains "$CLI_MAPPINGS" "8215.hat.4=next chat"
assert_contains "$CLI_MAPPINGS" "8215.hat.6=toggle sidebar"

# CLI: verify the intended Joy-Con usages and unchanged stick directions.
assert_contains "$CLI_MAPPINGS" "8199.button.1=hold dictation"
assert_contains "$CLI_MAPPINGS" "8199.button.2=toggle Voice Chat"
assert_contains "$CLI_MAPPINGS" "8199.button.3=send"
assert_contains "$CLI_MAPPINGS" "8199.button.4=clear input"
assert_contains "$CLI_MAPPINGS" "8199.button.5=toggle Voice Chat microphone"
assert_contains "$CLI_MAPPINGS" "8199.button.6=expand browser/content panel"
assert_contains "$CLI_MAPPINGS" "8199.button.10=new chat"
assert_contains "$CLI_MAPPINGS" "8199.button.13=focus ChatGPT"
assert_contains "$CLI_MAPPINGS" "8199.button.15=toggle Voice Chat microphone"
assert_contains "$CLI_MAPPINGS" "8199.hat.0=toggle sidebar"
assert_contains "$CLI_MAPPINGS" "8199.hat.2=previous chat"
assert_contains "$CLI_MAPPINGS" "8199.hat.4=toggle side panel"
assert_contains "$CLI_MAPPINGS" "8199.hat.6=next chat"
assert_not_contains "$CLI_MAPPINGS" "8199.button.6=toggle Voice Chat microphone"
assert_not_contains "$CLI_MAPPINGS" "8199.button.10=focus ChatGPT"
assert_not_contains "$CLI_MAPPINGS" "8199.button.15=new chat"

assert_contains "$CLI_HELP" "  SR            -> Control + Command + Z"
assert_contains "$CLI_HELP" "  R             -> Control + Option + Command + M"
assert_contains "$CLI_HELP" "  +             -> Command + N"
assert_contains "$CLI_HELP" "  Home          -> focus ChatGPT"

# Both paths must emit Ryan's exact Control-Command-Z custom shortcut.
assert_file_contains "$ROOT_DIR/SNESChatGPTMenuBar.swift" \
  'focusThenPost(KeyStroke(keyCode: 6, flags: [.maskControl, .maskCommand]))'
assert_file_contains "$ROOT_DIR/SNESChatGPTMapper.swift" \
  'focusThenPost(KeyStroke(keyCode: 6, flags: [.maskControl, .maskCommand]))'

echo "All controller mapping tests passed."
