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
