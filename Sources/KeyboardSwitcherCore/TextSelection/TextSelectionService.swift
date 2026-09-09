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
            return nil
        }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard status == .success else {
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
        postWithCommandKey(down: down, up: up)

        // Bounded wait for the frontmost app to fulfil the copy (condition polling, not a blind sleep).
        let timeout: TimeInterval = 0.3
        var waited: TimeInterval = 0
        while pasteboard.changeCount == changeCountBefore && waited < timeout {
            usleep(20_000)
            waited += 0.02
        }
        guard pasteboard.changeCount != changeCountBefore,
              let copied = pasteboard.string(forType: .string), !copied.isEmpty else {
            return nil
        }
        return copied
    }

    public func replaceSelectedText(with text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if let element = focusedElement(),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            // WebKit-based apps may report success without applying the write;
            // verify by re-reading the selection (spec §3.4).
            if verifyWrite(element: element, expected: text) {
                return true
            }
            return finishReplace(text)
        }
        return finishReplace(text)
    }

    /// Returns false when the selection still holds other text (the write was a no-op).
    /// A failed/empty re-read means the selection collapsed, i.e. the write applied.
    private func verifyWrite(element: AXUIElement, expected: String) -> Bool {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard status == .success, let current = value as? String else { return true }
        return current == expected
    }

    /// The paste fallback for every app. ChatGPT-class apps ignore synthetic ⌘V
    /// (session- and HID-level, with full modifier streams) and fake-success AX writes,
    /// so their Paste menu item is pressed via AX instead (spec §3.4).
    private func finishReplace(_ text: String) -> Bool {
        if isChatGPT {
            return replaceViaMenuPaste(text)
        }
        return pasteViaClipboard(text)
    }

    private var isChatGPT: Bool {
        // The ChatGPT desktop app reports com.openai.codex on this machine;
        // com.openai.chat is its identifier on other installs.
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return bundleID == "com.openai.codex" || bundleID == "com.openai.chat"
    }

    /// Save clipboard → copy translated text → AX-press the app's Paste menu item
    /// → restore clipboard (per setting). Menu actions are dispatched by the app
    /// itself, so they work where synthetic key events are ignored.
    private func replaceViaMenuPaste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        // Give the pasteboard a moment before pressing Paste.
        usleep(50_000)
        guard pressPasteMenuItem() else {
            NSPasteboard.general.clearContents()
            if let saved {
                NSPasteboard.general.setString(saved, forType: .string)
            }
            return false
        }
        if shouldRestoreClipboard() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSPasteboard.general.clearContents()
                if let saved {
                    NSPasteboard.general.setString(saved, forType: .string)
                }
            }
        }
        return true
    }

    /// Presses the frontmost app's Edit → Paste menu item via AX, matched by its
    /// ⌘V key equivalent so it works regardless of menu language.
    private func pressPasteMenuItem() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(frontmost.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return false
        }
        return pressPasteItem(in: menuBar as! AXUIElement, depth: 3)
    }

    private func pressPasteItem(in element: AXUIElement, depth: Int) -> Bool {
        guard depth >= 0 else { return false }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }
        for child in children {
            if isPasteMenuItem(child) {
                return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
            }
            if pressPasteItem(in: child, depth: depth - 1) {
                return true
            }
        }
        return false
    }

    private func isPasteMenuItem(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              (roleRef as? String) == "AXMenuItem" else {
            return false
        }
        // "AXMenuItemCmdChar"/"AXMenuItemCmdModifiers" are the command-equivalent
        // attributes; matching by key equivalent avoids menu-language assumptions.
        var cmdCharRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXMenuItemCmdChar" as CFString, &cmdCharRef) == .success,
              (cmdCharRef as? String)?.uppercased() == "V" else {
            return false
        }
        var modifiersRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXMenuItemCmdModifiers" as CFString, &modifiersRef) == .success,
              (modifiersRef as? NSNumber)?.intValue == 0 else { // 0 = Command only
            return false
        }
        return true
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
        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            NSPasteboard.general.clearContents()
            if let saved {
                NSPasteboard.general.setString(saved, forType: .string)
            }
            return false
        }
        postWithCommandKey(down: down, up: up)
        if shouldRestoreClipboard() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSPasteboard.general.clearContents()
                if let saved {
                    NSPasteboard.general.setString(saved, forType: .string)
                }
            }
        }
        return true
    }

    /// Posts a command-key combination as a full physical stream: ⌘ down (flagsChanged),
    /// key down, key up, ⌘ up. WebKit-based editors track modifier state transitions
    /// and drop key equivalents that appear without them.
    private func postWithCommandKey(down: CGEvent, up: CGEvent) {
        down.flags = .maskCommand
        up.flags = .maskCommand
        postCommandFlagsChanged(pressed: true)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        postCommandFlagsChanged(pressed: false)
    }

    private func postCommandFlagsChanged(pressed: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: pressed) else {
            return
        }
        event.type = .flagsChanged
        event.flags = pressed ? .maskCommand : []
        event.post(tap: .cghidEventTap)
    }
}
