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
