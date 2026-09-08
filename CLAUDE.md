# CLAUDE.md

Guidance for working on this repository.

## What this is

**keyboard-switcher** — a macOS menu bar utility that fixes text typed in the wrong keyboard layout.

The user types text while the wrong input source is active (e.g., Ukrainian words typed on an English layout produce `ghbdtn` instead of `привет`). They select the text, press a hotkey, and the utility:

1. Switches the input source to the other language
2. Remaps the selected text key-by-key using the physical-key mapping between the two layouts (deterministic translation, not machine translation — fully offline)

`docs/concept.md` is the product source of truth. If implementation questions arise about behavior, resolve them against that file.

## Product requirements (from concept)

- Menu bar app (`LSUIElement`, no Dock icon) with a keyboard-style icon, chosen during UI work
- Menu bar click menu: **Settings / About / Exit**
- Settings popup: configure languages manually **or** take them from system input sources
- With more than two input sources enabled, the hotkey cycles to the next language and translates the selection to it

## Stack

- Swift 5.9, SwiftUI + AppKit, target macOS 14+ (arm64)
- SwiftPM as the build backbone (`swift build` / `swift test` from CLI)
- Packaging into a signed `.app` bundle happens later via a bundle script; do not add an Xcode project unless asked
- No third-party dependencies initially; system frameworks only:

| Concern | API |
|---|---|
| Input source enumeration / switching | `TISCopyCurrentKeyboardInputSource`, `TISSelectInputSource` (Carbon) |
| Hotkey registration | `RegisterEventHotKey` (Carbon) |
| Selected text capture / replacement | AX API (`AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`) |
| Menu bar UI | SwiftUI `MenuBarExtra` |

## Runtime permissions

The AX API requires the user to grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Expect and handle the "not granted" state; running from CLI means the permission is granted to the terminal app.

## Commands

```bash
swift build          # debug build
swift test           # unit tests
swift run            # run the menubar app
```

## Planned architecture

Small, isolated units behind clear interfaces:

- `MenuBarController` — menu bar item, menu, settings/about windows
- `HotkeyManager` — global hotkey registration and callback
- `TextSelectionService` — read/replace selected text in the frontmost app via AX API
- `InputSourceService` — enumerate, order, and switch input sources via TIS
- `KeymapTranslator` — pure mapping logic: given two keyboard layouts, translate text; must be unit-testable with no AppKit dependencies

## Conventions

- Commits are authored by the repo owner only (Stas <travmik@gmail.com>); no bot attribution in commit messages
- Keymap translation logic lives in pure, testable functions — it is the heart of the app and must be covered by unit tests
