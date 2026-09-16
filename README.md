# Cursor Mobile companion

Unofficial iOS client plus a desktop companion for [Cursor](https://cursor.com). It is **not** the App Store Cursor app.

The iPhone UI follows the Cursor Mobile screenshots in [`images/`](images/). The companion on your computer signs in with your real Cursor account, indexes **local** desktop and CLI chats, and lets the phone control agents (including Yes/No permission prompts).

## What you get

- **iOS (SwiftUI)** — Inbox, agent lists, chat, subagents, Plan/Ask/Debug/Multitask, context-usage ring, Live Activities
- **Companion (macOS, Windows, Linux)** — Electron tray app, Bonjour pairing, `@cursor/sdk` login (365-day API key), ACP (`agent acp`) for local runs
- **GitHub Releases** — unsigned `.ipa`, `.dmg`, `.AppImage`, `.exe`

## How it works

1. Install and open **Cursor Mobile Companion** on the computer that already runs Cursor.
2. Click **Sign in with Cursor** (browser login; key stored in `~/.cursor/sdk/auth.json`, 365-day TTL).
3. Enter the 6-digit pairing code in the iOS app on the same network.
4. Inbox fills from the Cursor app database, CLI transcripts, and cloud agents.

The phone never receives your API key. Local chats never leave the computer except over the paired LAN WebSocket.

Cloud-only API key mode on the phone **cannot** see desktop/CLI history.

## Requirements

- Companion: Node.js 22.13+ to develop; Cursor CLI (`agent`) on `PATH` for local follow-ups and permission prompts
- iOS: iOS 17+, Xcode 16+ to build
- Same local network (Bonjour `_cursormobile._tcp`)

## Develop

```bash
# Companion
cd companion
npm install
npm start

# iOS
cd ios/CursorMobile
xcodegen generate
xcodebuild -scheme CursorMobile -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## Unsigned installers

An unsigned `.ipa` cannot be installed on a stock iPhone until you sign it with your Apple team. Unsigned `.dmg` / `.AppImage` / `.exe` will show Gatekeeper or SmartScreen warnings.

```bash
./scripts/build-ios.sh      # dist/CursorMobile-unsigned.ipa
cd companion && npm run dist:mac
```

Linux AppImage and Windows exe are produced by the Release workflow (and AppImage can be built in Docker).

## Permission prompts

Local agents run through Cursor ACP so tool calls can block. The phone shows **Yes**, **No**, **Always allow**, and a **permission mode** control (Allowlist / Auto-review / Run Everything). Cloud agents do not use Run Modes and will not prompt.

## License

MIT. Cursor is a trademark of Anysphere. This project is an unofficial companion.
