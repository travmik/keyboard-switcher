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
