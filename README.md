# ChatGPT SNES Mapper

A tiny macOS menu-bar app that turns the official Nintendo Bluetooth SNES controller into a ChatGPT Desktop macropad.

It watches the SNES controller over HID, shows controller/permission status in the menu bar, and sends keyboard shortcuts to ChatGPT Desktop.

This project is unofficial and is not affiliated with OpenAI, ChatGPT, or Nintendo.

## Controller Map

| SNES control | Action |
| --- | --- |
| Start / Select | Open or focus ChatGPT |
| A | Hold ChatGPT dictation (`Control + Shift + D`) |
| B | Send message (`Return`) |
| X / Y | Start or stop Voice Chat (`Control + Shift + V`) |
| L / R | Toggle Voice Chat microphone (`Control + Option + Command + M`) |
| ZR | Lock or unlock the mapper; locked mode ignores every controller input except ZR |
| D-pad Up / Down | Step through visible chat slots (`Command + 1` through `Command + 9`) |
| D-pad Left / Right | Unused |

The mapper is calibrated for the official Nintendo SNES Controller:

- Vendor ID: `0x057E`
- Product ID: `0x2017`

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools, for `swiftc`
- ChatGPT Desktop installed at `/Applications/ChatGPT.app`
- The official Nintendo Bluetooth SNES Controller paired with macOS

## Install

```bash
./scripts/install.sh
```

This builds:

- Menu-bar app: `~/.local/share/chatgpt-snes-mapper/ChatGPTSNESMapper.app`
- CLI helper: `~/.local/bin/chatgpt-snes-mapper`
- LaunchAgent: `~/Library/LaunchAgents/io.github.ryanfoxeth.chatgpt-snes-mapper.plist`

The app launches as a menu-bar item.

## ChatGPT Shortcut Setup

In ChatGPT Desktop, open Settings > Keyboard shortcuts and confirm:

- `Toggle voice chat` is `Control + Shift + V`
- `Toggle Voice Chat microphone` is `Control + Option + Command + M`

The mic shortcut is usually unassigned by default, so L/R will not work until it is set.

## macOS Permissions

The app needs Accessibility permission so it can send keyboard shortcuts.

Open System Settings > Privacy & Security > Accessibility and enable:

- `ChatGPTSNESMapper.app`

Menu-bar status:

- `SNES`: controller connected and keyboard control allowed
- `SNES?`: waiting for the controller
- `SNES!`: controller connected, but keyboard control is blocked
- `SNES Off`: mapper locked; press ZR or use the menu to unlock

## CLI

Run the mapper in the terminal:

```bash
chatgpt-snes-mapper
```

Print raw controller usages:

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

Build into a temporary directory without installing:

```bash
APP_BUNDLE_PATH=/tmp/chatgpt-snes-mapper/ChatGPTSNESMapper.app \
CLI_PATH=/tmp/chatgpt-snes-mapper/chatgpt-snes-mapper \
./scripts/build.sh
```

Use monitor mode to calibrate a different controller:

```bash
~/.local/bin/chatgpt-snes-mapper --monitor
```

Contributions are welcome. Good next improvements include configurable mappings, support for more controllers, and better chat-list navigation once ChatGPT exposes a more precise shortcut.

## License

MIT. See [LICENSE](LICENSE).
