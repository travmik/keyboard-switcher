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
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
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
