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
