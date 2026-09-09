# keyboard-switcher — Design Spec (Increment 1: full concept)

Date: 2026-09-08
Status: approved in chat, pending written-spec review
Source of truth for product intent: `docs/concept.md`

## 1. Overview

A macOS menu bar utility that fixes text typed with the wrong keyboard layout active. The user selects mistyped text (e.g., Ukrainian typed on an English layout → `ghbdtn`), presses **⌥⌘K**, and the app replaces the selection with the text remapped key-by-key to the other layout, then switches the input source so typing continues in the correct language.

The remapping is deterministic (physical-key → character mapping between two layouts), not machine translation. Fully offline.

## 2. Goals / Non-goals

**Goals (this increment):**
- Global hotkey ⌥⌘K: capture selection → translate → replace → switch input source
- More than two input sources: hotkey cycles to the next enabled language (wraps around)
- Menu bar icon (keyboard symbol) with Settings… / About / Quit
- Settings: checkbox list of system input sources (enabled ones form the cycle); Accessibility permission status; hotkey display
- Languages taken from system input sources (per concept)
- Packaged as `LSUIElement` .app via `scripts/make-app.sh`; `swift run` works for development

**Non-goals (later increments):**
- Hotkey rebinding UI (⌥⌘K is fixed this increment; displayed in Settings)
- Option-layer / dead-key character remapping (diacritics pass through)
- Custom (non-system) language definitions
- Auto-detection of typed language without selection (Punto-style "convert last word")

## 3. Architecture

Six isolated units. Each has one purpose, a small interface, and is testable without the system APIs it wraps.

```
KeyboardSwitcherApp (SwiftUI lifecycle, .accessory policy, MenuBarExtra)
        │
   Orchestrator ──── the only component that knows the full sequence
     ├── HotkeyManager        registers ⌥⌘K via Carbon RegisterEventHotKey, fires callback
     ├── TextSelectionService AX API: read kAXSelectedText, write it back;
     │                        on AX write failure → clipboard-paste fallback
     ├── InputSourceService   TIS: list enabled sources, current source, select next
     └── KeymapTranslator     PURE: translate(text, sourceKeymap, targetKeymap)
        │
   KeymapProvider           UCKeyTranslate-based extraction of char tables per
                            layout ID; cached; feeds KeymapTranslator
```

**Dependency rule:** UI → Orchestrator → Services; `KeymapTranslator` and the keymap data model depend on nothing but the standard library. Services are wrapped behind protocols so the Orchestrator is testable with mocks.

### 3.1 Orchestrator sequence (on hotkey)

1. Read current input source (pre-switch layout) via `InputSourceService`
2. Compute next enabled source: `(index of current in enabled list + 1) mod count`; if the current source is not in the enabled list, target the first enabled source
3. Capture selected text via `TextSelectionService`; empty → abort (no-op)
4. Load keymaps for current + next layout via `KeymapProvider`
5. `translated = KeymapTranslator.translate(text, source: currentKeymap, target: nextKeymap)`
6. Replace selection via `TextSelectionService` (AX write, fallback to clipboard dance)
7. Switch input source to next via `InputSourceService`

Replacement happens before the switch: the AX write and the ⌘V paste are layout-independent, and after step 7 the user keeps typing in the new layout.

### 3.2 KeymapTranslator (pure)

- Keymap model: `Keymap` = base layer `[keyCode: Character]` + shift layer `[keyCode: Character]`.
- Build reverse map `char → (keyCode, needsShift)` from the source keymap.
- Per input character:
  - Look up `(keyCode, needsShift)` in the source reverse map; not found → pass character through unchanged.
  - Target char = `needsShift ? target.shift[keyCode] : target.base[keyCode]`; missing → pass through.
- Case-sensitive by construction: lowercase source chars map to base layer, uppercase to shift layer — case survives translation in both directions.
- Punctuation remaps like letters (same keyCode mechanism), so `,`/`?`-class corrections work.

### 3.3 KeymapProvider (UCKeyTranslate extraction)

- For a given `TISInputSource`: get `kTISPropertyUnicodeKeyLayoutData`, call `UCKeyTranslate` with `kUCKeyActionDisplay` for modifiers = 0 (base) and `shiftKey` (shift layer), over virtual key codes 0…127.
- Cache by layout ID (`kTISPropertyInputSourceID`).
- Skip non-keyboard sources (layouts only — filter by type `kTISTypeKeyboardLayout`), so input methods don't enter the cycle list.

### 3.4 TextSelectionService

- Read: `AXUIElementCreateSystemWide` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`.
- **Read fallback** (amended 2026-09-09, post-acceptance bug: Electron/Chromium apps do not expose the selection via AX, so the read returns nil and the hotkey silently no-oped): when the AX read yields nothing, read the selection via the clipboard — save pasteboard string → synthesize ⌘C (`kVK_ANSI_C` + cmd, `.cgSessionEventTap`) → poll `changeCount` for up to ~300 ms → return the copied string. Unchanged `changeCount` (nothing selected, or the app refuses copy) → restore the saved string and return nil.
- Write: set `kAXSelectedTextAttribute` on the same focused element.
- Write fallback (AX write returns non-`.success`):
  1. Save `NSPasteboard.general` string content (empty → nothing to restore)
  2. Copy translated text to pasteboard
  3. Post synthetic keyDown/keyUp ⌘V (`CGEvent`, `kVK_ANSI_V` + cmd flag) to `.cgSessionEventTap`
  4. Clipboard restore is **off by default** (setting `restoreClipboardAfterFix`, added 2026-09-09): slow-paste apps (ChatGPT's web editor consumes paste asynchronously) read the pasteboard after the 200 ms restore window and pasted the restored pre-paste content, making the fix a no-op. When the setting is on, the saved string is restored ~200 ms after the paste.
- Known MVP limitation: non-string pasteboard contents (images, files) are not restored; when both the AX read and the AX write fail (pure-clipboard round trip), the intermediate clipboard snapshots make the pre-hotkey clipboard unrestorable in that double-fallback path; documented in code.

### 3.5 HotkeyManager

- `RegisterEventHotKey` with keyCode `kVK_ANSI_K` (40), modifiers `optionKey | cmdKey`, on install; `UnregisterEventHotKey` on teardown. No rebinding this increment.

### 3.6 InputSourceService

- Enabled keyboard layouts: `TISCreateInputSourceList(nil, false)` filtered to `kTISTypeKeyboardLayout`
- Current: `TISCopyCurrentKeyboardInputSource`; Select: `TISSelectInputSource`
- Source identity: input source ID string (`kTISPropertyInputSourceID`), e.g. `com.apple.keylayout.US`

## 4. UI

SwiftUI `MenuBarExtra` (`.menuBarExtraStyle(.menu)`, SF Symbol `keyboard`):

- **Settings…** — separate `NSWindow` hosting a SwiftUI view:
  - Checkbox list of system keyboard layouts in system order; checked = participates in the hotkey cycle
  - Accessibility status row: granted ✓ / not granted + "Open System Settings" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`)
  - Hotkey row: "Translate & switch: ⌥⌘K" (display only)
- **About** — small window: app name, version (from bundle/build), one-line description
- **Quit** — terminates

Windows are managed by a small `WindowController` (AppKit) hosting SwiftUI content — avoids SwiftUI window-lifecycle quirks inside MenuBarExtra-only apps.

### 4.1 Persistence

`AppSettings` (Codable → `UserDefaults`):
```swift
struct AppSettings: Codable {
    var enabledSourceIDs: [String]        // ordered; the hotkey cycle order
    var restoreClipboardAfterFix: Bool    // default false
}
```
First launch: all detected keyboard layouts enabled. Removing a layout from the system that is still in settings is tolerated (filtered out at read time). Empty/invalid settings → re-enable all.

## 5. Error handling

| Case | Behavior |
|---|---|
| No text selected | no-op |
| Fewer than 2 enabled layouts | no-op |
| AX permission not granted | no-op on hotkey; Settings shows status + deep link |
| Character not in either keymap | passes through unchanged |
| AX write fails | clipboard-paste fallback |
| AX read fails or yields nothing (Electron/Chromium) | clipboard-copy fallback: ⌘C → pasteboard read → translate → replace path as usual |
| Clipboard fallback while pasteboard holds non-string | replace works; original non-string content not restored (documented) |
| Layout missing from KeymapProvider cache | extract on demand; extraction failure → no-op with console log |
| Settings reference a removed system layout | ignored at read time |

## 6. Repo structure

```
Package.swift                      (swift-tools-version 5.9, macOS .v14)
Sources/KeyboardSwitcher/
  KeyboardSwitcherApp.swift        entry, MenuBarExtra, accessory policy
  Orchestrator/
    Orchestrator.swift
    SettingsStore.swift            AppSettings + UserDefaults persistence
  Keymap/
    Keymap.swift                   data model
    KeymapTranslator.swift         pure logic
    KeymapProvider.swift           UCKeyTranslate extraction + cache
  InputSource/
    InputSourceService.swift
  TextSelection/
    TextSelectionService.swift
  Hotkey/
    HotkeyManager.swift
  UI/
    MenuController.swift           WindowController, Settings + About windows
    SettingsView.swift
    AboutView.swift
Tests/KeyboardSwitcherTests/
  KeymapTranslatorTests.swift      fixture keymaps: en↔ua, case, punctuation, passthrough
  OrchestratorTests.swift          cycle logic + call order with mocked services
  SettingsStoreTests.swift         persistence round-trip, stale-ID filtering
scripts/make-app.sh                assembles build/KeyboardSwitcher.app
                                   (Info.plist: LSUIElement, CFBundleIdentifier)
```

## 7. Testing strategy

- **KeymapTranslator**: unit tests with small hand-written fixture keymaps (no Carbon): en↔ua round trip, mixed case, punctuation remap, unmappable passthrough (digits, emoji), empty string.
- **Orchestrator**: mocked protocol implementations; verify cycle order, no-op guards, and call sequence (capture → translate → replace → switch).
- **SettingsStore**: round-trip persistence + stale layout-ID filtering.
- **System wrappers** (`KeymapProvider`, `TextSelectionService`, `InputSourceService`, `HotkeyManager`): thin, verified manually against real apps (TextEdit = AX path; Chrome = fallback path); no automated tests this increment.

## 8. Permissions & packaging

- Accessibility permission required (AX read/write of focused element). Checked passively; the app never prompts from the hotkey path.
- `swift run` for development: permission attaches to the terminal app; `.accessory` activation policy set at startup so no Dock icon appears.
- `scripts/make-app.sh` builds the SwiftPM binary into `build/KeyboardSwitcher.app` with `LSUIElement=true` — the daily-use form; Accessibility is granted to the .app.

## 9. Acceptance criteria

1. `swift build` and `swift test` pass from a clean clone
2. With two system layouts (e.g., US + Ukrainian), selecting `ghbdtn` and pressing ⌥⌘K yields `привет` and the active layout becomes Ukrainian
3. Reverse direction works identically (`руддщ` → `hello`)
4. With three enabled layouts, repeated presses cycle through all three, translating each time
5. Works in TextEdit (AX path) and a browser (fallback path)
6. Menu bar shows icon; Settings lists system layouts with persisted checkboxes; About and Quit function
7. App runs without Dock icon, from both `swift run` and the packaged .app
