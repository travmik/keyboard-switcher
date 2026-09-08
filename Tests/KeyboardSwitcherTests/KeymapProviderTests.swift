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
