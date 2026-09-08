import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads and replaces the selected text of the focused element via the AX API.
/// Falls back to a clipboard paste when the app rejects the AX write (spec §3.4).
public final class TextSelectionService: TextSelectionServicing {

    public init() {}

    public func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    public func replaceSelectedText(with text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if let element = focusedElement(),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            return true
        }
        return pasteViaClipboard(text)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let element = value else { return nil }
        return (element as! AXUIElement)
    }

    /// Save clipboard → copy translated text → synthetic ⌘V → restore clipboard.
    /// MVP limitation: only string clipboard contents are restored (spec §3.4).
    private func pasteViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }

        // Give the pasteboard a moment before synthesizing ⌘V.
        usleep(50_000)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) else {
            NSPasteboard.general.clearContents()
            if let saved {
                NSPasteboard.general.setString(saved, forType: .string)
            }
            return false
        }
        down.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            NSPasteboard.general.clearContents()
            if let saved {
                NSPasteboard.general.setString(saved, forType: .string)
            }
            return false
        }
        up.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSPasteboard.general.clearContents()
            if let saved {
                NSPasteboard.general.setString(saved, forType: .string)
            }
        }
        return true
    }
}
