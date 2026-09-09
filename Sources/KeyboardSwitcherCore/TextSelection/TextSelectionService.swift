import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads and replaces the selected text of the focused element via the AX API.
/// Falls back to a clipboard paste when the app rejects the AX write (spec §3.4).
public final class TextSelectionService: TextSelectionServicing {

    private let shouldRestoreClipboard: () -> Bool

    /// - Parameter shouldRestoreClipboard: consulted after every paste; when false
    ///   (the default) the clipboard keeps the translated text instead of the
    ///   pre-paste content.
    public init(shouldRestoreClipboard: @escaping () -> Bool = { false }) {
        self.shouldRestoreClipboard = shouldRestoreClipboard
    }

    public func selectedText() -> String? {
        guard let element = focusedElement() else {
            debugLog("AX: no focused element") // TEMPORARY DEBUG
            return nil
        }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard status == .success else {
            debugLog("AX read failed: \(status.rawValue)") // TEMPORARY DEBUG
            return nil
        }
        return value as? String
    }

    /// Read fallback for apps that don't expose the selection via AX (Electron/Chromium):
    /// synthetic ⌘C → poll the pasteboard → return the copied selection (spec §3.4).
    /// On success the pasteboard intentionally holds the selection; the replace path
    /// (AX write, or the ⌘V fallback) proceeds from there. On failure the pasteboard
    /// was never touched.
    public func selectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            return nil
        }
        down.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)

        // Bounded wait for the frontmost app to fulfil the copy (condition polling, not a blind sleep).
        let timeout: TimeInterval = 0.3
        var waited: TimeInterval = 0
        while pasteboard.changeCount == changeCountBefore && waited < timeout {
            usleep(20_000)
            waited += 0.02
        }
        guard pasteboard.changeCount != changeCountBefore,
              let copied = pasteboard.string(forType: .string), !copied.isEmpty else {
            debugLog("⌘C fallback: copy did not land (change=\(pasteboard.changeCount))") // TEMPORARY DEBUG
            return nil
        }
        debugLog("⌘C fallback: captured \(copied.count) chars") // TEMPORARY DEBUG
        return copied
    }

    public func replaceSelectedText(with text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if let element = focusedElement(),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            debugLog("replace: AX write OK") // TEMPORARY DEBUG
            return true
        }
        debugLog("replace: AX write failed -> ⌘V paste fallback") // TEMPORARY DEBUG
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
        if shouldRestoreClipboard() {
            debugLog("paste: ⌘V posted, clipboard restore in 200ms") // TEMPORARY DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSPasteboard.general.clearContents()
                if let saved {
                    NSPasteboard.general.setString(saved, forType: .string)
                }
            }
        } else {
            debugLog("paste: ⌘V posted, clipboard left with translated text") // TEMPORARY DEBUG
        }
        return true
    }
}

