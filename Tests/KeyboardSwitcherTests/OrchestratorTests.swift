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
