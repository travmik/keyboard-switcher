# keyboard-switcher

A macOS menu bar utility that fixes text typed in the wrong keyboard layout.

Typed Ukrainian words while the English layout was active — got `ghbdtn` instead of `привет`? Select the text, press the hotkey: the input source switches and the selected text is remapped key-by-key to the other language.

## Status

**Concept stage.** See [docs/concept.md](docs/concept.md) for the product idea. Implementation has not started.

## Planned features

- Global hotkey: switch layout + "translate" the selected text between layouts
- Menu bar item with Settings / About / Exit
- Language setup in settings, or taken from system input sources
- Support for more than two input sources (hotkey cycles through them)

## Build

Swift 5.9, macOS 14+ (arm64), SwiftPM:

```bash
swift build          # debug build
swift test           # unit tests
swift run            # run from CLI for development
./scripts/make-app.sh  # assemble build/KeyboardSwitcher.app for daily use
```

The app requires **Accessibility** permission (System Settings → Privacy & Security →
Accessibility) to read and replace selected text. Grant it to `KeyboardSwitcher.app`
(or to your terminal app when running via `swift run`).

## License

[MIT](LICENSE)
