# ChatGPT Controller Mapper

A tiny macOS menu-bar app that turns supported Nintendo Bluetooth controllers into a ChatGPT Desktop macropad.

It watches the controller over HID, shows controller/permission status in the menu bar, and sends keyboard shortcuts to ChatGPT Desktop.

This project is unofficial and is not affiliated with OpenAI, ChatGPT, or Nintendo.

![SNES controller map](assets/snes-controller-map.png?v=20260810)

## SNES Controller Map

| SNES control | Action |
| --- | --- |
| Start / Select | Open or focus ChatGPT |
| A | Hold ChatGPT dictation (`Control + Shift + D`) |
| B | Send message (`Return`) |
| X | Start or stop Voice Chat (`Control + Shift + V`) |
| Y | Clear the current input (`Command + A`, then `Delete`) |
| L / R | Toggle Voice Chat microphone (`Control + Option + Command + M`) |
| ZL | Start a new chat (`Command + N`) |
| ZR | Lock or unlock the mapper; locked mode ignores every controller input except ZR |
| D-pad Up | Previous chat (`Shift + Command + [`) |
| D-pad Down | Next chat (`Shift + Command + ]`) |
| D-pad Left | Toggle the sidebar (`Command + B`) |
| D-pad Right | Toggle the side/review panel (`Option + Command + B`) |

The built-in default preset is `ChatGPT Voice Macropad`; use the menu-bar app's `Load Default Preset` item to restore the selected controller profile. Use the `Mappings` menu to change a control's action. SNES and Joy-Con custom mappings are saved independently with macOS `UserDefaults` and survive relaunch.

## Joy-Con (R) Map

![Joy-Con (R) controller map](assets/joycon-r-controller-map.png?v=20260814)

The right Joy-Con has profile-specific defaults while leaving every SNES mapping unchanged:

| Joy-Con (R) control | Action |
| --- | --- |
| + | Start a new chat (`Command + N`) |
| Home | Open or focus ChatGPT |
| A | Hold ChatGPT dictation (`Control + Shift + D`) |
| B | Send message (`Return`) |
| X | Start or stop Voice Chat (`Control + Shift + V`) |
| Y | Clear the current input (`Command + A`, then `Delete`) |
| SL | Close the current tab or window (`Command + W`) |
| SR | Expand the browser/content panel with Ryan's custom shortcut (`Control + Command + Z`) |
| R | Toggle Voice Chat microphone (`Control + Option + Command + M`) |
| ZR | Lock or unlock the mapper |
| Stick Up | Previous chat (`Shift + Command + [`) |
| Stick Down | Next chat (`Shift + Command + ]`) |
| Stick Left | Toggle the sidebar (`Command + B`) |
| Stick Right | Toggle the side/review panel (`Option + Command + B`) |

The Joy-Con profile was calibrated against real HID events from a Bluetooth-connected Nintendo Switch Joy-Con (R). Its vertical stick orientation uses a different hat-switch rotation than the SNES controller, which the mapper handles per device.

## Controller Selection

Use the menu-bar app's `Controller Mode` submenu:

- `Automatic` watches for both supported controller IDs. Either controller works when connected, and both remain active if they are connected together.
- `SNES Controller` ignores Joy-Con input and waits for the SNES controller when it is disconnected.
- `Joy-Con (R)` ignores SNES input and waits for the right Joy-Con when it is disconnected.

The selected mode is saved in macOS `UserDefaults` and survives relaunch. Automatic is the default.

## Supported Controllers

- Official Nintendo Bluetooth SNES Controller: vendor `0x057E`, product `0x2017`
- Nintendo Switch Joy-Con (R): vendor `0x057E`, product `0x2007`

The left Joy-Con has a different physical layout and is not enabled by this profile. Calibrate it separately with monitor mode before adding product `0x2006`.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools, for `swiftc`
- ChatGPT Desktop installed at `/Applications/ChatGPT.app`
- A supported Nintendo Bluetooth controller paired with macOS

## Install

Build the app directly into Applications:

```bash
APP_BUNDLE_PATH="/Applications/ChatGPT Controller Mapper.app" \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/build.sh
open -g "/Applications/ChatGPT Controller Mapper.app"
```

Use a stable Apple Development or Developer ID Application signing identity for the installed app. This lets macOS associate the Accessibility grant with the same app across rebuilds. The build automatically selects the first valid Developer ID Application identity, then Apple Development, when one is available. You can select a specific identity by setting `CODESIGN_IDENTITY` to its SHA-1 fingerprint from `security find-identity -v -p codesigning`. Set it to `-` to force ad-hoc signing, which may make macOS require Accessibility permission again after each rebuild.

Or install the per-user app and LaunchAgent:

```bash
./scripts/install.sh
```

This builds:

- Menu-bar app: `~/.local/share/chatgpt-snes-mapper/ChatGPTSNESMapper.app`
- CLI helper: `~/.local/bin/chatgpt-snes-mapper`
- LaunchAgent: `~/Library/LaunchAgents/io.github.ryanfoxeth.chatgpt-snes-mapper.plist`

The app launches as a menu-bar item.

Check the installed app's current Accessibility status directly:

```bash
"/Applications/ChatGPT Controller Mapper.app/Contents/MacOS/ChatGPTSNESMapper" \
  --check-accessibility
```

## Required ChatGPT Shortcuts

Before using the Joy-Con R and SR actions, open ChatGPT Settings > Keyboard shortcuts and assign:

- `Toggle Voice Chat Microphone` to `Control + Option + Command + M`
- The browser/content side-panel expansion action to `Control + Command + Z` (Ryan's custom shortcut)

These are prerequisites: Joy-Con R uses the microphone shortcut, and Joy-Con SR uses the browser/content side-panel shortcut. Joy-Con SL sends the standard macOS `Command + W` shortcut and requires no ChatGPT shortcut setting.

## macOS Permissions

The app needs Accessibility permission so it can send keyboard shortcuts.

Open System Settings > Privacy & Security > Accessibility and enable:

- `ChatGPT Controller Mapper`

Menu-bar status:

- `SNES`: controller connected and keyboard control allowed
- `JOY`: right Joy-Con connected and keyboard control allowed
- `PAD`: both supported controllers connected in Automatic mode
- `PAD?`: waiting for a supported controller
- `SNES!`: controller connected, but keyboard control is blocked
- `JOY!`: right Joy-Con connected, but keyboard control is blocked
- `SNES Off` / `JOY Off`: mapper locked; press ZR or use the menu to unlock

## CLI

Run the mapper in the terminal:

```bash
chatgpt-snes-mapper
```

Print controller names and raw HID usages without sending keyboard shortcuts:

```bash
chatgpt-snes-mapper --monitor
```

## Uninstall

```bash
./scripts/uninstall.sh
```

This removes the LaunchAgent and stops the app. It leaves the built app and CLI in place.

## Privacy and Security

The app does not send network requests, store credentials, or read ChatGPT content. It listens for HID events from the configured controller and posts macOS keyboard events.

Because macOS treats keyboard-event posting as computer control, the menu-bar app requires Accessibility permission. Review the source before granting that permission, especially if you modify the app.

## Development

Run the build and mapping regression tests:

```bash
./scripts/test.sh
```

Build into a temporary directory without installing:

```bash
APP_BUNDLE_PATH=/tmp/chatgpt-snes-mapper/ChatGPTSNESMapper.app \
CLI_PATH=/tmp/chatgpt-snes-mapper/chatgpt-snes-mapper \
./scripts/build.sh
```

Use monitor mode to calibrate another controller:

```bash
~/.local/bin/chatgpt-snes-mapper --monitor
```

Contributions are welcome. Good next improvements include import/export for mapping presets and a separately calibrated Joy-Con (L) profile.

## License

MIT. See [LICENSE](LICENSE).
