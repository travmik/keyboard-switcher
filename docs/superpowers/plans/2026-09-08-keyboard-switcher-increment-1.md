# keyboard-switcher Increment 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full concept (spec §2 Goals): ⌥⌘K captures the selected text, translates it key-by-key to the next enabled layout, replaces it, and switches the input source; menu bar app with Settings/About/Quit.

**Architecture:** SwiftPM package with two targets — `KeyboardSwitcherCore` (all logic: keymap model/translator, UCKeyTranslate extraction, TIS input sources, AX text selection, hotkey, orchestrator, settings) and `KeyboardSwitcher` (executable: SwiftUI MenuBarExtra UI). The two-target split is a deliberate deviation from the spec's single-directory sketch: test targets cannot reliably link an executable target, and the spec requires the core to be unit-testable. Pure logic is TDD'd with fixture keymaps; thin system-API wrappers are verified manually (spec §7).

**Tech Stack:** Swift 5.9 (swift-tools-version:5.9), macOS 14+ arm64, SwiftUI/AppKit/Carbon HIToolbox/ApplicationServices, zero third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-08-keyboard-switcher-design.md` — read it before starting; section numbers below reference it.

## Global Constraints

- macOS 14+ (`.macOS(.v14)`), swift-tools-version 5.9, no third-party dependencies
- Commit author/committer: `Stas <travmik@gmail.com>` (repo-local git config already set). Never mention Claude, AI, or automation in commit messages; never add co-author trailers.
- UI copy in English; hotkey fixed to ⌥⌘K this increment (spec §2 Non-goals)
- Core logic (KeymapTranslator, Orchestrator, SettingsStore) is unit-tested; system wrappers (InputSourceService, KeymapProvider, TextSelectionService, HotkeyManager) are compile-checked and verified manually in Task 10 (spec §7)
- UCKeyTranslate modifier states: 0 = base layer, 1 = shift layer (bit 0 of the modifier mask is Shift)
- Carbon constants used below: `kVK_ANSI_K` = 40, `kVK_ANSI_V` = 9, `cmdKey` = 256, `optionKey` = 2048

## File Structure

```
Package.swift
Sources/KeyboardSwitcherCore/
  Keymap/Keymap.swift                 data model (base+shift char tables)
  Keymap/KeymapTranslator.swift       pure translation logic
  Keymap/KeymapProvider.swift         UCKeyTranslate extraction + cache, KeymapProviding
  Services/ServiceProtocols.swift     InputSourceServicing, TextSelectionServicing, KeymapProviding, InputSourceInfo
  Services/Log.swift                  stderr logging helper
  Services/SettingsStore.swift        AppSettings + UserDefaults persistence
  Orchestrator/Orchestrator.swift     hotkey sequence: capture → translate → replace → switch
  InputSource/TISLookup.swift          shared TIS lookup helpers (ID, lookup-by-ID, name, type filter)
  InputSource/InputSourceService.swift   TIS implementation of InputSourceServicing
  TextSelection/TextSelectionService.swift  AX implementation of TextSelectionServicing (+ clipboard fallback)
  Hotkey/HotkeyManager.swift          Carbon RegisterEventHotKey (⌥⌘K)
Sources/KeyboardSwitcher/
  KeyboardSwitcherApp.swift           @main, MenuBarExtra, AppDelegate, .accessory policy
  UI/MenuController.swift             NSWindow lifecycle for Settings/About
  UI/SettingsView.swift               layout checkboxes, permission row, hotkey row
  UI/AboutView.swift                  about window content
Tests/KeyboardSwitcherTests/
  KeymapTranslatorTests.swift
  SettingsStoreTests.swift
  OrchestratorTests.swift
  KeymapProviderTests.swift           smoke test of the Carbon extraction path
scripts/make-app.sh                  release build → build/KeyboardSwitcher.app (LSUIElement)
```

---

### Task 1: Package skeleton + Keymap model + KeymapTranslator (TDD)

**Files:**
- Create: `Package.swift`
- Create: `Sources/KeyboardSwitcher/KeyboardSwitcherApp.swift` (stub, replaced in Task 8)
- Create: `Sources/KeyboardSwitcherCore/Keymap/Keymap.swift`
- Create: `Sources/KeyboardSwitcherCore/Keymap/KeymapTranslator.swift`
- Test: `Tests/KeyboardSwitcherTests/KeymapTranslatorTests.swift`

**Interfaces:**
- Consumes: nothing (first task)
- Produces:
  - `struct Keymap: Equatable` with `init(base: [UInt64: Character], shift: [UInt64: Character])`, properties `var base: [UInt64: Character]`, `var shift: [UInt64: Character]`
  - `enum KeymapTranslator` with `static func translate(_ text: String, source: Keymap, target: Keymap) -> String`
  - SwiftPM targets: `KeyboardSwitcherCore` (library), `KeyboardSwitcher` (executable), `KeyboardSwitcherTests`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "keyboard-switcher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeyboardSwitcherCore", path: "Sources/KeyboardSwitcherCore"),
        .executableTarget(
            name: "KeyboardSwitcher",
            dependencies: ["KeyboardSwitcherCore"],
            path: "Sources/KeyboardSwitcher"
        ),
        .testTarget(
            name: "KeyboardSwitcherTests",
            dependencies: ["KeyboardSwitcherCore"],
            path: "Tests/KeyboardSwitcherTests"
        )
    ]
)
```

- [ ] **Step 2: Create the executable stub** at `Sources/KeyboardSwitcher/KeyboardSwitcherApp.swift` (so the package builds; full UI arrives in Task 8)

```swift
import SwiftUI

@main
struct KeyboardSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra("Keyboard Switcher", systemImage: "keyboard") {
            Button("Quit Keyboard Switcher") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 3: Write the failing tests** at `Tests/KeyboardSwitcherTests/KeymapTranslatorTests.swift`

Fixtures are synthetic keymaps modeled on US ↔ macOS Ukrainian ("ЙЦУКЕН") with real `kVK_ANSI_*` key codes. They exercise translation logic; real keymaps come from `KeymapProvider` at runtime (Task 5).

```swift
import XCTest
@testable import KeyboardSwitcherCore

final class KeymapTranslatorTests: XCTestCase {

    // MARK: Fixtures (kVK_ANSI_* codes)

    private let en = Keymap(
        base: [
            12: "q", 13: "w", 14: "e", 15: "r", 17: "t", 16: "y", 32: "u", 34: "i", 31: "o", 35: "p",
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 45: "n", 46: "m", 37: "l",
            41: ";", 43: ",", 47: ".", 44: "/", 33: "[", 30: "]", 39: "'", 42: "\\", 27: "-", 50: "`"
        ],
        shift: [
            12: "Q", 13: "W", 14: "E", 15: "R", 17: "T", 16: "Y", 32: "U", 34: "I", 31: "O", 35: "P",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 45: "N", 46: "M", 37: "L",
            41: ":", 43: "<", 47: ">", 44: "?", 33: "{", 30: "}", 39: "\"", 42: "|", 27: "_", 50: "~"
        ]
    )

    private let ua = Keymap(
        base: [
            12: "й", 13: "ц", 14: "у", 15: "к", 17: "е", 16: "н", 32: "г", 34: "ш", 31: "щ", 35: "з",
            0: "ф", 1: "і", 2: "в", 3: "а", 4: "р", 5: "п", 6: "я", 7: "ч", 8: "с", 9: "м",
            11: "и", 45: "т", 46: "ь", 37: "д",
            41: "ж", 43: "б", 47: "ю", 44: ".", 33: "х", 30: "ї", 39: "є", 42: "\\", 27: "-", 50: "\u{2019}"
        ],
        shift: [
            12: "Й", 13: "Ц", 14: "У", 15: "К", 17: "Е", 16: "Н", 32: "Г", 34: "Ш", 31: "Щ", 35: "З",
            0: "Ф", 1: "І", 2: "В", 3: "А", 4: "Р", 5: "П", 6: "Я", 7: "Ч", 8: "С", 9: "М",
            11: "И", 45: "Т", 46: "Ь", 37: "Д",
            41: "Ж", 43: "Б", 47: "Ю", 44: ",", 33: "Х", 30: "Ї", 39: "Є", 42: "\\", 27: "_", 50: "'"
        ]
    )

    // MARK: Tests

    func test_ukrainianTypedOnEnglishLayout() {
        XCTAssertEqual(KeymapTranslator.translate("ghbdtn", source: en, target: ua), "привет")
    }

    func test_englishTypedOnUkrainianLayout() {
        XCTAssertEqual(KeymapTranslator.translate("руддщ", source: ua, target: en), "hello")
    }

    func test_preservesCase() {
        XCTAssertEqual(KeymapTranslator.translate("Ghbdtn", source: en, target: ua), "Привет")
        XCTAssertEqual(KeymapTranslator.translate("Руддщ", source: ua, target: en), "Hello")
    }

    func test_remapsPunctuation() {
        // "?" is Shift+/ on US; same key is "," (shifted) on Ukrainian
        XCTAssertEqual(KeymapTranslator.translate("?", source: en, target: ua), ",")
        // ";" sits where "ж" lives on Ukrainian
        XCTAssertEqual(KeymapTranslator.translate("ж", source: ua, target: en), ";")
        XCTAssertEqual(KeymapTranslator.translate("[", source: en, target: ua), "х")
    }

    func test_unmappableCharactersPassThrough() {
        XCTAssertEqual(KeymapTranslator.translate("abc 123!", source: en, target: ua), "фис 123!")
    }

    func test_emptyString() {
        XCTAssertEqual(KeymapTranslator.translate("", source: en, target: ua), "")
    }

    func test_roundTrip() {
        let original = "Hello, World!"
        let toUa = KeymapTranslator.translate(original, source: en, target: ua)
        let back = KeymapTranslator.translate(toUa, source: ua, target: en)
        XCTAssertEqual(back, original)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --filter KeymapTranslatorTests`
Expected: FAIL — compile error "cannot find 'Keymap' in scope" (red step)

- [ ] **Step 5: Implement the model and translator**

`Sources/KeyboardSwitcherCore/Keymap/Keymap.swift`:

```swift
import Foundation

/// Character tables of one keyboard layout.
/// Keys are virtual key codes (`kVK_*`); `base` is the unshifted layer, `shift` the shifted layer.
public struct Keymap: Equatable {
    public var base: [UInt64: Character]
    public var shift: [UInt64: Character]

    public init(base: [UInt64: Character], shift: [UInt64: Character]) {
        self.base = base
        self.shift = shift
    }
}
```

`Sources/KeyboardSwitcherCore/Keymap/KeymapTranslator.swift`:

```swift
import Foundation

/// Pure key-by-key text translation between two layouts (spec §3.2).
public enum KeymapTranslator {

    public static func translate(_ text: String, source: Keymap, target: Keymap) -> String {
        var reverse: [Character: (keyCode: UInt64, needsShift: Bool)] = [:]
        for (keyCode, char) in source.base {
            reverse[char] = (keyCode, false)
        }
        // Base layer wins if a char is produced in both layers.
        for (keyCode, char) in source.shift where reverse[char] == nil {
            reverse[char] = (keyCode, true)
        }

        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            guard let entry = reverse[char] else {
                result.append(char)
                continue
            }
            if let mapped = entry.needsShift ? target.shift[entry.keyCode] : target.base[entry.keyCode] {
                result.append(mapped)
            } else {
                result.append(char)
            }
        }
        return result
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter KeymapTranslatorTests`
Expected: PASS, 7 tests

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: keymap model and pure layout translator"
```

---

### Task 2: SettingsStore (TDD)

**Files:**
- Create: `Sources/KeyboardSwitcherCore/Services/SettingsStore.swift`
- Test: `Tests/KeyboardSwitcherTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `struct AppSettings: Codable, Equatable` with `init(enabledSourceIDs: [String] = [])`, property `var enabledSourceIDs: [String]`
  - `final class SettingsStore` with `init(defaults: UserDefaults = .standard)`, `func load() -> AppSettings`, `func save(_ settings: AppSettings)`

- [ ] **Step 1: Write the failing tests** at `Tests/KeyboardSwitcherTests/SettingsStoreTests.swift`

```swift
import XCTest
@testable import KeyboardSwitcherCore

final class SettingsStoreTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SettingsStoreTests")
        defaults.removePersistentDomain(forName: "SettingsStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SettingsStoreTests")
        super.tearDown()
    }

    func test_loadReturnsEmptySettingsWhenNothingStored() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), AppSettings(enabledSourceIDs: []))
    }

    func test_saveThenLoadRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        let settings = AppSettings(enabledSourceIDs: ["com.apple.keylayout.US", "com.apple.keylayout.Ukrainian"])
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func test_corruptDataLoadsAsEmpty() {
        defaults.set(Data("not json".utf8), forKey: "AppSettings")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), AppSettings(enabledSourceIDs: []))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — compile error "cannot find 'SettingsStore' in scope"

- [ ] **Step 3: Implement** `Sources/KeyboardSwitcherCore/Services/SettingsStore.swift`

```swift
import Foundation

public struct AppSettings: Codable, Equatable {
    public var enabledSourceIDs: [String]

    public init(enabledSourceIDs: [String] = []) {
        self.enabledSourceIDs = enabledSourceIDs
    }
}

/// Persists app settings as JSON in UserDefaults (spec §4.1).
public final class SettingsStore {
    private let defaults: UserDefaults
    private static let storageKey = "AppSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.storageKey) else { return AppSettings() }
        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS, 3 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/KeyboardSwitcherCore/Services/SettingsStore.swift Tests/KeyboardSwitcherTests/SettingsStoreTests.swift
git commit -m "feat: settings persistence in UserDefaults"
```

---

### Task 3: Service protocols + Orchestrator (TDD)

**Files:**
- Create: `Sources/KeyboardSwitcherCore/Services/ServiceProtocols.swift`
- Create: `Sources/KeyboardSwitcherCore/Services/Log.swift`
- Create: `Sources/KeyboardSwitcherCore/Orchestrator/Orchestrator.swift`
- Test: `Tests/KeyboardSwitcherTests/OrchestratorTests.swift`

**Interfaces:**
- Consumes: `Keymap`, `KeymapTranslator.translate(_:source:target:)` (Task 1), `AppSettings`, `SettingsStore` (Task 2)
- Produces (used by Tasks 4–6 implementations and the Task 8 app wiring):
  - `struct InputSourceInfo: Equatable` with `init(id: String, localizedName: String)`, properties `let id: String`, `let localizedName: String`
  - `protocol InputSourceServicing`: `func enabledLayouts() -> [InputSourceInfo]`, `func currentLayoutID() -> String?`, `func selectLayout(id: String) -> Bool`
  - `protocol TextSelectionServicing`: `func selectedText() -> String?`, `func replaceSelectedText(with text: String) -> Bool`
  - `protocol KeymapProviding`: `func keymap(forSourceID id: String) -> Keymap?`
  - `public func logError(_ message: String)` — writes `keyboard-switcher: <message>` to stderr
  - `final class Orchestrator` with `init(inputSource: InputSourceServicing, textSelection: TextSelectionServicing, keymaps: KeymapProviding, settings: SettingsStore)`, `func switchAndTranslate()`, `func resolvedEnabledSourceIDs() -> [String]`

- [ ] **Step 1: Define the service protocols** at `Sources/KeyboardSwitcherCore/Services/ServiceProtocols.swift`

```swift
import Foundation

public struct InputSourceInfo: Equatable {
    public let id: String
    public let localizedName: String

    public init(id: String, localizedName: String) {
        self.id = id
        self.localizedName = localizedName
    }
}

public protocol InputSourceServicing {
    func enabledLayouts() -> [InputSourceInfo]
    func currentLayoutID() -> String?
    func selectLayout(id: String) -> Bool
}

public protocol TextSelectionServicing {
    func selectedText() -> String?
    func replaceSelectedText(with text: String) -> Bool
}

public protocol KeymapProviding {
    func keymap(forSourceID id: String) -> Keymap?
}
```

- [ ] **Step 2: Add the logging helper** at `Sources/KeyboardSwitcherCore/Services/Log.swift`

```swift
import Foundation

public func logError(_ message: String) {
    FileHandle.standardError.write(Data("keyboard-switcher: \(message)\n".utf8))
}
```

- [ ] **Step 3: Write the failing tests** at `Tests/KeyboardSwitcherTests/OrchestratorTests.swift`

```swift
import XCTest
@testable import KeyboardSwitcherCore

// MARK: - Mocks

private final class Recorder {
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}

private final class MockInputSource: InputSourceServicing {
    let layouts: [InputSourceInfo]
    var currentID: String?
    private let recorder: Recorder?

    var selectedLayoutID: String?

    init(layouts: [InputSourceInfo], currentID: String?, recorder: Recorder? = nil) {
        self.layouts = layouts
        self.currentID = currentID
        self.recorder = recorder
    }

    func enabledLayouts() -> [InputSourceInfo] { layouts }

    func currentLayoutID() -> String? {
        recorder?.add("current")
        return currentID
    }

    func selectLayout(id: String) -> Bool {
        recorder?.add("select")
        selectedLayoutID = id
        return true
    }
}

private final class MockTextSelection: TextSelectionServicing {
    var text: String?
    var replaceResult = true
    var replacedWith: String?
    private let recorder: Recorder?

    init(text: String?, recorder: Recorder? = nil) {
        self.text = text
        self.recorder = recorder
    }

    func selectedText() -> String? {
        recorder?.add("selectedText")
        return text
    }

    func replaceSelectedText(with text: String) -> Bool {
        recorder?.add("replace")
        replacedWith = text
        return replaceResult
    }
}

private final class MockKeymaps: KeymapProviding {
    var map: [String: Keymap]

    init(map: [String: Keymap]) {
        self.map = map
    }

    func keymap(forSourceID id: String) -> Keymap? {
        map[id]
    }
}

// MARK: - Tests

final class OrchestratorTests: XCTestCase {

    private static let suiteName = "OrchestratorTests"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suiteName)!.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)!.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private let enID = "com.apple.keylayout.US"
    private let uaID = "com.apple.keylayout.Ukrainian"
    private let deID = "com.apple.keylayout.German"

    private var enKeymap: Keymap {
        Keymap(base: [0: "a", 1: "b"], shift: [0: "A", 1: "B"])
    }

    private var uaKeymap: Keymap {
        Keymap(base: [0: "ф", 1: "и"], shift: [0: "Ф", 1: "И"])
    }

    private var deKeymap: Keymap {
        Keymap(base: [0: "x"], shift: [0: "X"])
    }

    private func makeInfo(_ ids: [String]) -> [InputSourceInfo] {
        ids.map { InputSourceInfo(id: $0, localizedName: $0) }
    }

    func test_translatesSelectionAndSwitchesToNextLayout() {
        let recorder = Recorder()
        let input = MockInputSource(layouts: makeInfo([enID, uaID]), currentID: enID, recorder: recorder)
        let selection = MockTextSelection(text: "ab", recorder: recorder)
        let keymaps = MockKeymaps(map: [enID: enKeymap, uaID: uaKeymap])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
        let orchestrator = Orchestrator(inputSource: input, textSelection: selection, keymaps: keymaps, settings: settings)

        orchestrator.switchAndTranslate()

        XCTAssertEqual(selection.replacedWith, "фи")
        XCTAssertEqual(input.selectedLayoutID, uaID)
    }

    func test_wrapsAroundFromLastToFirst() {
        let input = MockInputSource(layouts: makeInfo([enID, uaID]), currentID: uaID)
        let selection = MockTextSelection(text: "a")
        let keymaps = MockKeymaps(map: [enID: enKeymap, uaID: uaKeymap])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
        let orchestrator = Orchestrator(inputSource: input, textSelection: selection, keymaps: keymaps, settings: settings)

        orchestrator.switchAndTranslate()

        XCTAssertEqual(input.selectedLayoutID, enID)
    }

    func test_currentLayoutNotEnabled_targetsFirstEnabled() {
        let input = MockInputSource(layouts: makeInfo([enID, uaID]), currentID: deID)
        let selection = MockTextSelection(text: "a")
        let keymaps = MockKeymaps(map: [enID: enKeymap, uaID: uaKeymap, deID: deKeymap])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
        let orchestrator = Orchestrator(inputSource: input, textSelection: selection, keymaps: keymaps, settings: settings)

        orchestrator.switchAndTranslate()

        XCTAssertEqual(input.selectedLayoutID, enID)
    }

    func test_fewerThanTwoEnabledLayouts_noOp() {
        let input = MockInputSource(layouts: makeInfo([enID]), currentID: enID)
        let selection = MockTextSelection(text: "ab")
        let keymaps = MockKeymaps(map: [enID: enKeymap])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
        settings.save(AppSettings(enabledSourceIDs: [enID]))
        let orchestrator = Orchestrator(inputSource: input, textSelection: selection, keymaps: keymaps, settings: settings)

        orchestrator.switchAndTranslate()

        XCTAssertNil(selection.replacedWith)
        XCTAssertNil(input.selectedLayoutID)
    }

    func test_noSelectedText_noOp() {
        let input = MockInputSource(layouts: makeInfo([enID, uaID]), currentID: enID)
        let selection = MockTextSelection(text: nil)
        let keymaps = MockKeymaps(map: [enID: enKeymap, uaID: uaKeymap])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
        let orchestrator = Orchestrator(inputSource: input, textSelection: selection, keymaps: keymaps, settings: settings)

        orchestrator.switchAndTranslate()

        XCTAssertNil(selection.replacedWith)
        XCTAssertNil(input.selectedLayoutID)
    }

    func test_replacesBeforeSwitching() {
        let recorder = Recorder()
        let input = MockInputSource(layouts: makeInfo([enID, uaID]), currentID: enID, recorder: recorder)
        let selection = MockTextSelection(text: "ab", recorder: recorder)
        let keymaps = MockKeymaps(map: [enID: enKeymap, uaID: uaKeymap])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
        let orchestrator = Orchestrator(inputSource: input, textSelection: selection, keymaps: keymaps, settings: settings)

        orchestrator.switchAndTranslate()

        XCTAssertEqual(recorder.entries, ["current", "selectedText", "replace", "select"])
    }

    func test_switchesLayoutEvenIfReplaceFails() {
        let input = MockInputSource(layouts: makeInfo([enID, uaID]), currentID: enID)
        let selection = MockTextSelection(text: "ab")
        selection.replaceResult = false
        let keymaps = MockKeymaps(map: [enID: enKeymap, uaID: uaKeymap])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
        let orchestrator = Orchestrator(inputSource: input, textSelection: selection, keymaps: keymaps, settings: settings)

        orchestrator.switchAndTranslate()

        XCTAssertEqual(input.selectedLayoutID, uaID)
    }

    func test_resolvedEnabledSources_filtersStaleIDs_andFallsBackToAll() {
        let input = MockInputSource(layouts: makeInfo([enID, uaID]), currentID: enID)
        let keymaps = MockKeymaps(map: [:])
        let settings = SettingsStore(defaults: UserDefaults(suiteName: Self.suiteName)!)

        // Stale ID (German) is not in the system list → filtered out
        settings.save(AppSettings(enabledSourceIDs: [uaID, deID]))
        let orchestrator = Orchestrator(inputSource: input, textSelection: MockTextSelection(text: nil), keymaps: keymaps, settings: settings)
        XCTAssertEqual(orchestrator.resolvedEnabledSourceIDs(), [uaID])

        // Empty settings → all system layouts
        settings.save(AppSettings(enabledSourceIDs: []))
        XCTAssertEqual(orchestrator.resolvedEnabledSourceIDs(), [enID, uaID])
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --filter OrchestratorTests`
Expected: FAIL — compile error "cannot find 'Orchestrator' in scope"

- [ ] **Step 5: Implement** `Sources/KeyboardSwitcherCore/Orchestrator/Orchestrator.swift`

```swift
import Foundation

/// Coordinates the hotkey sequence (spec §3.1):
/// read current layout → resolve target → capture selection → translate → replace → switch.
public final class Orchestrator {
    private let inputSource: InputSourceServicing
    private let textSelection: TextSelectionServicing
    private let keymaps: KeymapProviding
    private let settings: SettingsStore

    public init(inputSource: InputSourceServicing,
                textSelection: TextSelectionServicing,
                keymaps: KeymapProviding,
                settings: SettingsStore) {
        self.inputSource = inputSource
        self.textSelection = textSelection
        self.keymaps = keymaps
        self.settings = settings
    }

    public func switchAndTranslate() {
        guard let currentID = inputSource.currentLayoutID() else {
            logError("could not determine current input source")
            return
        }

        let enabled = resolvedEnabledSourceIDs()
        guard enabled.count >= 2 else { return }

        // Current layout not in the enabled list → target the first enabled one (spec §3.1).
        let targetID: String
        if let index = enabled.firstIndex(of: currentID) {
            targetID = enabled[(index + 1) % enabled.count]
        } else {
            targetID = enabled[0]
        }

        guard let text = textSelection.selectedText(), !text.isEmpty else { return }
        guard let sourceKeymap = keymaps.keymap(forSourceID: currentID),
              let targetKeymap = keymaps.keymap(forSourceID: targetID) else {
            logError("no keymap for \(currentID) or \(targetID)")
            return
        }

        let translated = KeymapTranslator.translate(text, source: sourceKeymap, target: targetKeymap)
        if !textSelection.replaceSelectedText(with: translated) {
            logError("could not replace selection")
        }
        if !inputSource.selectLayout(id: targetID) {
            logError("could not switch input source to \(targetID)")
        }
    }

    /// Enabled layout IDs: saved settings minus IDs no longer present in the system;
    /// empty (first launch or all stale) → all system layouts (spec §4.1).
    func resolvedEnabledSourceIDs() -> [String] {
        let systemIDs = inputSource.enabledLayouts().map(\.id)
        let saved = settings.load().enabledSourceIDs.filter { systemIDs.contains($0) }
        return saved.isEmpty ? systemIDs : saved
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter OrchestratorTests`
Expected: PASS, 8 tests

- [ ] **Step 7: Commit**

```bash
git add Sources/KeyboardSwitcherCore Tests/KeyboardSwitcherTests/OrchestratorTests.swift
git commit -m "feat: orchestrator with language cycling and translation flow"
```

---

### Task 4: InputSourceService (TIS implementation)

**Files:**
- Create: `Sources/KeyboardSwitcherCore/InputSource/TISLookup.swift`
- Create: `Sources/KeyboardSwitcherCore/InputSource/InputSourceService.swift`

**Interfaces:**
- Consumes: `InputSourceServicing`, `InputSourceInfo` (Task 3)
- Produces:
  - `enum TISLookup` with `static func inputSourceID(of source: TISInputSource) -> String?`, `static func findInputSource(withID id: String) -> TISInputSource?`, `static func localizedName(of source: TISInputSource) -> String?`, `static func isKeyboardLayout(_ source: TISInputSource) -> Bool`
  - `final class InputSourceService: InputSourceServicing` with `init()`

No unit tests: thin TIS wrapper, verified manually in Task 10 (spec §7).

- [ ] **Step 1: Implement** `Sources/KeyboardSwitcherCore/InputSource/TISLookup.swift`

```swift
import Carbon.HIToolbox
import Foundation

/// Shared TIS helpers for identifying and finding input sources.
/// Property keys are global CFString constants, hence takeUnretainedValue.
enum TISLookup {

    private static let keyboardLayoutType = "TISTypeKeyboardLayout" // kTISTypeKeyboardLayout

    static func inputSourceID(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID.takeUnretainedValue()) else {
            return nil
        }
        return unsafeBitCast(pointer, to: CFString.self) as String?
    }

    static func findInputSource(withID id: String) -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return nil }
        for source in list as! [TISInputSource] {
            if inputSourceID(of: source) == id { return source }
        }
        return nil
    }

    static func localizedName(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName.takeUnretainedValue()) else {
            return nil
        }
        return unsafeBitCast(pointer, to: CFString.self) as String?
    }

    /// True for keyboard layouts; excludes input methods so they never enter the
    /// hotkey cycle (spec §3.3).
    static func isKeyboardLayout(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType.takeUnretainedValue()) else {
            return false
        }
        let type = unsafeBitCast(pointer, to: CFString.self) as String? ?? ""
        return type == keyboardLayoutType
    }
}
```

- [ ] **Step 2: Implement** `Sources/KeyboardSwitcherCore/InputSource/InputSourceService.swift`

```swift
import Carbon.HIToolbox
import Foundation

/// TIS-based implementation of input source enumeration and switching (spec §3.6).
public final class InputSourceService: InputSourceServicing {

    public init() {}

    /// Enabled keyboard layouts in system order.
    public func enabledLayouts() -> [InputSourceInfo] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        var result: [InputSourceInfo] = []
        for source in list as! [TISInputSource] {
            guard TISLookup.isKeyboardLayout(source),
                  let id = TISLookup.inputSourceID(of: source),
                  let name = TISLookup.localizedName(of: source) else { continue }
            result.append(InputSourceInfo(id: id, localizedName: name))
        }
        return result
    }

    public func currentLayoutID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return TISLookup.inputSourceID(of: current)
    }

    public func selectLayout(id: String) -> Bool {
        guard let source = TISLookup.findInputSource(withID: id) else { return false }
        return TISSelectInputSource(source) == noErr
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git add Sources/KeyboardSwitcherCore/InputSource
git commit -m "feat: input source enumeration and switching via TIS"
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add Sources/KeyboardSwitcherCore/InputSource
git commit -m "feat: input source enumeration and switching via TIS"
```

---

### Task 5: KeymapProvider (UCKeyTranslate extraction)

**Files:**
- Create: `Sources/KeyboardSwitcherCore/Keymap/KeymapProvider.swift`
- Test: `Tests/KeyboardSwitcherTests/KeymapProviderTests.swift` (smoke test of the Carbon path)

**Interfaces:**
- Consumes: `Keymap` (Task 1), `KeymapProviding` (Task 3), `TISLookup` (Task 4)
- Produces:
  - `final class KeymapProvider: KeymapProviding` with `init()`, `func keymap(forSourceID id: String) -> Keymap?`
  - `static func extractKeymap(from source: TISInputSource) -> Keymap?` (internal, reused by the smoke test)

- [ ] **Step 1: Write the failing smoke test** at `Tests/KeyboardSwitcherTests/KeymapProviderTests.swift`

```swift
import XCTest
@testable import KeyboardSwitcherCore

/// Smoke test for the UCKeyTranslate extraction path — runs on a real Mac with real layouts.
final class KeymapProviderTests: XCTestCase {

    func test_extractsKeymapForCurrentLayout() throws {
        let inputSource = InputSourceService()
        let currentID = try XCTUnwrap(inputSource.currentLayoutID(), "no current input source")
        let provider = KeymapProvider()
        let keymap = try XCTUnwrap(provider.keymap(forSourceID: currentID), "keymap extraction failed for \(currentID)")

        // A real layout produces a substantial table on both layers.
        XCTAssertGreaterThan(keymap.base.count, 20)
        XCTAssertGreaterThan(keymap.shift.count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeymapProviderTests`
Expected: FAIL — compile error "cannot find 'KeymapProvider' in scope"

- [ ] **Step 3: Implement** `Sources/KeyboardSwitcherCore/Keymap/KeymapProvider.swift`

```swift
import Carbon.HIToolbox
import Foundation

/// Extracts a layout's character tables via UCKeyTranslate and caches them per
/// input source ID (spec §3.3). Modifier states: 0 = base, 1 = shift.
public final class KeymapProvider: KeymapProviding {

    private var cache: [String: Keymap] = [:]
    private let lock = NSLock()

    public init() {}

    public func keymap(forSourceID id: String) -> Keymap? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[id] { return cached }
        guard let source = TISLookup.findInputSource(withID: id),
              let keymap = Self.extractKeymap(from: source) else { return nil }
        cache[id] = keymap
        return keymap
    }

    static func extractKeymap(from source: TISInputSource) -> Keymap? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData.takeUnretainedValue()) else {
            return nil
        }
        let layoutData = unsafeBitCast(pointer, to: CFData.self) as Data

        var base: [UInt64: Character] = [:]
        var shift: [UInt64: Character] = [:]
        for keyCode: UInt64 in 0..<128 {
            if let char = translateKey(data: layoutData, keyCode: UInt16(keyCode), modifierState: 0) {
                base[keyCode] = char
            }
            if let char = translateKey(data: layoutData, keyCode: UInt16(keyCode), modifierState: 1) {
                shift[keyCode] = char
            }
        }
        return Keymap(base: base, shift: shift)
    }

    private static func translateKey(data: Data, keyCode: UInt16, modifierState: UInt32) -> Character? {
        data.withUnsafeBytes { raw -> Character? in
            guard let baseAddress = raw.baseAddress else { return nil }
            let layout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var outputLength = 0
            var chars = [UniChar](repeating: 0, count: 16)

            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &outputLength,
                &chars
            )
            guard status == noErr, outputLength > 0 else { return nil }
            let string = String(decoding: chars[0..<outputLength], as: UTF16.self)
            // Multi-char results (dead-key sequences) are not remapped this increment.
            guard string.count == 1, let char = string.first else { return nil }
            return char
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter KeymapProviderTests`
Expected: PASS, 1 test (run on the local Mac with real keyboard layouts)

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — all prior tests still green

- [ ] **Step 6: Commit**

```bash
git add Sources/KeyboardSwitcherCore/Keymap/KeymapProvider.swift Tests/KeyboardSwitcherTests/KeymapProviderTests.swift
git commit -m "feat: keymap extraction from system layouts via UCKeyTranslate"
```

---

### Task 6: TextSelectionService (AX API + clipboard fallback)

**Files:**
- Create: `Sources/KeyboardSwitcherCore/TextSelection/TextSelectionService.swift`

**Interfaces:**
- Consumes: `TextSelectionServicing` (Task 3)
- Produces: `final class TextSelectionService: TextSelectionServicing` with `init()`

No unit tests: AX wrapper, verified manually in Task 10 (spec §7).

- [ ] **Step 1: Implement** `Sources/KeyboardSwitcherCore/TextSelection/TextSelectionService.swift`

```swift
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads and replaces the selected text of the focused element via the AX API.
/// Falls back to a clipboard paste when the app rejects the AX write (spec §3.4).
public final class TextSelectionService: TextSelectionServicing {

    public init() {}

    public func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    public func replaceSelectedText(with text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if let element = focusedElement(),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            return true
        }
        return pasteViaClipboard(text)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let element = value else { return nil }
        return (element as! AXUIElement)
    }

    /// Save clipboard → copy translated text → synthetic ⌘V → restore clipboard.
    /// MVP limitation: only string clipboard contents are restored (spec §3.4).
    private func pasteViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }

        // Give the pasteboard a moment before synthesizing ⌘V.
        usleep(50_000)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) else {
            return false
        }
        down.flags = .maskCommand
        down.post(tap: .combinedSessionState)
        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return false
        }
        up.post(tap: .combinedSessionState)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSPasteboard.general.clearContents()
            if let saved {
                NSPasteboard.general.setString(saved, forType: .string)
            }
        }
        return true
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add Sources/KeyboardSwitcherCore/TextSelection
git commit -m "feat: selected text read/replace via AX with clipboard fallback"
```

---

### Task 7: HotkeyManager (Carbon)

**Files:**
- Create: `Sources/KeyboardSwitcherCore/Hotkey/HotkeyManager.swift`

**Interfaces:**
- Consumes: nothing new
- Produces: `final class HotkeyManager` with `init(handler: @escaping () -> Void)`, `func install() -> Bool`, `func uninstall()` — registers ⌥⌘K (`kVK_ANSI_K`, `optionKey | cmdKey`)

No unit tests: Carbon wrapper, verified manually in Task 10 (spec §7).

- [ ] **Step 1: Implement** `Sources/KeyboardSwitcherCore/Hotkey/HotkeyManager.swift`

```swift
import Carbon.HIToolbox
import Foundation

private final class HotkeyContext {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
}

/// Registers the global ⌥⌘K hotkey via Carbon RegisterEventHotKey (spec §3.5).
public final class HotkeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let context: HotkeyContext

    public init(handler: @escaping () -> Void) {
        context = HotkeyContext(handler: handler)
    }

    public func install() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(context).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotkeyCallback,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        var hotKeyID = EventHotKeyID(signature: OSType(0x4B_53_57_31) /* "KSW1" */, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return registerStatus == noErr
    }

    public func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
    }

    private static let hotkeyCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        _ = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        unsafeBitCast(userData, to: HotkeyContext.self).handler()
        return noErr
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add Sources/KeyboardSwitcherCore/Hotkey
git commit -m "feat: global hotkey registration (option-command-K)"
```

---

### Task 8: App wiring and UI (MenuBarExtra, Settings, About)

**Files:**
- Modify: `Sources/KeyboardSwitcher/KeyboardSwitcherApp.swift` (replaces Task 1 stub)
- Create: `Sources/KeyboardSwitcher/UI/MenuController.swift`
- Create: `Sources/KeyboardSwitcher/UI/SettingsView.swift`
- Create: `Sources/KeyboardSwitcher/UI/AboutView.swift`

**Interfaces:**
- Consumes: `Orchestrator`, `SettingsStore`/`AppSettings`, `InputSourceServicing`/`InputSourceInfo`, `HotkeyManager`, `logError` (all from Core, Tasks 1–7)
- Produces: the runnable app. `AppDelegate.showSettings()` / `showAbout()` are invoked from the `MenuBarExtra` menu.

- [ ] **Step 1: Replace** `Sources/KeyboardSwitcher/KeyboardSwitcherApp.swift` with the full version

```swift
import SwiftUI
import KeyboardSwitcherCore

@main
struct KeyboardSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Keyboard Switcher", systemImage: "keyboard") {
            Button("Settings…") { appDelegate.showSettings() }
            Button("About Keyboard Switcher") { appDelegate.showAbout() }
            Divider()
            Button("Quit Keyboard Switcher") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: Orchestrator?
    private var hotkeyManager: HotkeyManager?
    private let menuController = MenuController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let inputSource = InputSourceService()
        let textSelection = TextSelectionService()
        let keymaps = KeymapProvider()
        let settings = SettingsStore()
        orchestrator = Orchestrator(
            inputSource: inputSource,
            textSelection: textSelection,
            keymaps: keymaps,
            settings: settings
        )
        menuController.configure(settings: settings, inputSource: inputSource)

        let hotkey = HotkeyManager { [weak orchestrator] in
            orchestrator?.switchAndTranslate()
        }
        if !hotkey.install() {
            logError("failed to register hotkey option-command-K")
        }
        hotkeyManager = hotkey
    }

    func showSettings() { menuController.showSettings() }
    func showAbout() { menuController.showAbout() }
}
```

- [ ] **Step 2: Create** `Sources/KeyboardSwitcher/UI/MenuController.swift`

```swift
import AppKit
import SwiftUI
import KeyboardSwitcherCore

/// Owns the Settings and About windows, hosting SwiftUI views in AppKit windows
/// (spec §4: avoids SwiftUI window-lifecycle quirks inside MenuBarExtra-only apps).
@MainActor
final class MenuController {
    private var settingsStore: SettingsStore?
    private var inputSourceService: InputSourceServicing?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    func configure(settings: SettingsStore, inputSource: InputSourceServicing) {
        settingsStore = settings
        inputSourceService = inputSource
    }

    func showSettings() {
        guard let settingsStore, let inputSourceService else { return }
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Keyboard Switcher — Settings"
            window.contentView = NSHostingView(
                rootView: SettingsView(store: settingsStore, inputSource: inputSourceService)
            )
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        let window: NSWindow
        if let existing = aboutWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 180),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "About Keyboard Switcher"
            window.contentView = NSHostingView(rootView: AboutView())
            window.center()
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3: Create** `Sources/KeyboardSwitcher/UI/SettingsView.swift`

```swift
import AppKit
import ApplicationServices
import SwiftUI
import KeyboardSwitcherCore

struct SettingsView: View {
    let store: SettingsStore
    let inputSource: InputSourceServicing

    @State private var layouts: [InputSourceInfo] = []
    @State private var enabledIDs: Set<String> = []
    @State private var accessibilityGranted = true

    var body: some View {
        Form {
            Section {
                if layouts.isEmpty {
                    Text("No keyboard layouts found").foregroundStyle(.secondary)
                }
                ForEach(layouts, id: \.id) { layout in
                    Toggle(isOn: binding(for: layout.id)) {
                        Text(layout.localizedName)
                    }
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("Checked languages participate in the option-command-K cycle.")
            }

            Section("Hotkey") {
                HStack {
                    Text("Translate & switch")
                    Spacer()
                    Text("⌥⌘K").foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear(perform: reload)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabledIDs.contains(id) },
            set: { isOn in
                if isOn {
                    enabledIDs.insert(id)
                } else {
                    enabledIDs.remove(id)
                }
                persist()
            }
        )
    }

    private func reload() {
        layouts = inputSource.enabledLayouts()
        let systemIDs = Set(layouts.map(\.id))
        let saved = store.load().enabledSourceIDs.filter { systemIDs.contains($0) }
        enabledIDs = saved.isEmpty ? systemIDs : Set(saved)
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func persist() {
        let ordered = layouts.filter { enabledIDs.contains($0.id) }.map(\.id)
        store.save(AppSettings(enabledSourceIDs: ordered))
    }
}
```

- [ ] **Step 4: Create** `Sources/KeyboardSwitcher/UI/AboutView.swift`

```swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Keyboard Switcher")
                .font(.title2.bold())
            Text(versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Fixes text typed in the wrong keyboard layout.\nSelect the text and press ⌥⌘K.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 300, height: 180)
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "Version \(version)"
    }
}
```

- [ ] **Step 5: Build and run the full test suite**

Run: `swift build && swift test`
Expected: build SUCCESS, all tests PASS

- [ ] **Step 6: Manual smoke check (interactive)**

Run: `swift run` — verify the keyboard icon appears in the menu bar, the menu shows Settings… / About / Quit, both windows open, and Quit works. If executed non-interactively, leave the app running and report this step to the user to confirm visually.

- [ ] **Step 7: Commit**

```bash
git add Sources/KeyboardSwitcher
git commit -m "feat: menu bar UI with settings and about windows"
```

---

### Task 9: App bundle packaging + README

**Files:**
- Create: `scripts/make-app.sh`
- Modify: `README.md` (build section: add `scripts/make-app.sh` usage)

**Interfaces:**
- Consumes: SwiftPM release build of the `KeyboardSwitcher` executable
- Produces: `build/KeyboardSwitcher.app` (`LSUIElement`, bundle ID `com.travmik.keyboard-switcher`) — the daily-use form from spec §8

- [ ] **Step 1: Create** `scripts/make-app.sh`

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/KeyboardSwitcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>KeyboardSwitcher</string>
    <key>CFBundleDisplayName</key><string>Keyboard Switcher</string>
    <key>CFBundleIdentifier</key><string>com.travmik.keyboard-switcher</string>
    <key>CFBundleExecutable</key><string>KeyboardSwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cp .build/release/KeyboardSwitcher "$APP/Contents/MacOS/KeyboardSwitcher"
codesign --force --sign - "$APP"
echo "Built $APP"
```

- [ ] **Step 2: Make it executable and build the bundle**

Run: `chmod +x scripts/make-app.sh && ./scripts/make-app.sh`
Expected: ends with `Built build/KeyboardSwitcher.app`

- [ ] **Step 3: Update the README build section**

Replace the "## Build" section of `README.md` with:

````markdown
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
````

- [ ] **Step 4: Commit**

```bash
git add scripts/make-app.sh README.md
git commit -m "build: app bundle packaging script and docs"
```

---

### Task 10: Acceptance verification (spec §9)

**Files:**
- Modify: `README.md` (status line)

**Interfaces:**
- Consumes: the completed app
- Produces: verified acceptance criteria + README status update

- [ ] **Step 1: Clean full check**

Run: `swift package clean && swift build && swift test`
Expected: SUCCESS, all tests PASS

- [ ] **Step 2: Manual acceptance pass (interactive — requires the user at the machine)**

Grant Accessibility permission to the terminal app (or launch `./scripts/make-app.sh && open build/KeyboardSwitcher.app` and grant to the app), add a second layout if needed, then verify against spec §9:

1. TextEdit with `ghbdtn` selected → ⌥⌘K → becomes `привет`, layout switches to Ukrainian
2. `руддщ` selected → ⌥⌘K → becomes `hello`, layout switches to US
3. With three enabled layouts, repeated ⌥⌘K cycles through all three, translating each time
4. In a browser (Chrome): same flow works via the clipboard fallback
5. Settings checkboxes persist across app restarts
6. No Dock icon in either launch mode

Report results honestly; any failed criterion is a bug to fix before claiming completion.

- [ ] **Step 3: Update README status**

Replace `**Concept stage.** See [docs/concept.md](docs/concept.md) for the product idea. Implementation has not started.` with:

```markdown
**Working prototype (increment 1 complete).** See [docs/concept.md](docs/concept.md) for the product idea and [docs/superpowers/specs/2026-09-08-keyboard-switcher-design.md](docs/superpowers/specs/2026-09-08-keyboard-switcher-design.md) for the increment 1 design.
```

- [ ] **Step 4: Commit and push**

```bash
git add README.md
git commit -m "docs: increment 1 complete"
git push
```

---

## Task dependency summary

Tasks 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 are sequential: each consumes the interfaces of earlier tasks. Tasks 4, 5, 6, 7 depend on Task 3's protocols but are independent of each other (may be parallelized if executing with isolated worktrees, merging in order 4 → 5 → 6 → 7).

## Plan self-review notes

- Spec coverage: §2 Goals → Tasks 1–9; §3.1 sequence → Task 3 (order test `test_replacesBeforeSwitching`); §3.2 → Task 1; §3.3 → Task 5; §3.4 → Task 6; §3.5 → Task 7; §3.6 → Task 4; §4 UI → Task 8; §4.1 persistence + stale filtering → Tasks 2–3; §5 error handling → guard paths in Tasks 3/6; §6 structure → two-target adaptation explained in Architecture; §7 testing → TDD tasks + manual Task 10; §8 permissions/packaging → Tasks 6/8/9; §9 acceptance → Task 10
- Known deliberate deviations from spec §6 sketch: `Sources/KeyboardSwitcherCore` target added (testability, explained in Architecture); shared TIS helpers extracted into `TISLookup` (Task 4) so `InputSourceService` and `KeymapProvider` don't depend on each other; `KeymapProviding` keyed by source ID (not `TISInputSource`) so the Orchestrator is mockable

