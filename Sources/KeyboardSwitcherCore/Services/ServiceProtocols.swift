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
    /// Clipboard-based read for apps that do not expose the selection via AX (spec §3.4 read fallback).
    func selectedTextViaClipboard() -> String?
    func replaceSelectedText(with text: String) -> Bool
}

public protocol KeymapProviding {
    func keymap(forSourceID id: String) -> Keymap?
}
