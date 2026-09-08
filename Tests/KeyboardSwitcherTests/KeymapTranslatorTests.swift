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
