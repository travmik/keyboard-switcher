import Carbon.HIToolbox
import Foundation

/// Shared TIS helpers for identifying and finding input sources.
/// Property keys are global CFString constants imported directly (no Unmanaged wrapper).
enum TISLookup {

    private static let keyboardLayoutType = "TISTypeKeyboardLayout" // kTISTypeKeyboardLayout

    static func inputSourceID(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
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
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        return unsafeBitCast(pointer, to: CFString.self) as String?
    }

    /// True for keyboard layouts; excludes input methods so they never enter the
    /// hotkey cycle (spec §3.3).
    static func isKeyboardLayout(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else {
            return false
        }
        let type = unsafeBitCast(pointer, to: CFString.self) as String? ?? ""
        return type == keyboardLayoutType
    }
}
