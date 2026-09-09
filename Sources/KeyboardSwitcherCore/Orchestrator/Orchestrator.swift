import Foundation

/// Coordinates the hotkey sequence (spec §3.1):
/// read current layout → resolve target → capture selection → translate → replace → switch.
public final class Orchestrator {
    private let inputSource: InputSourceServicing
    private let textSelection: TextSelectionServicing
    private let keymaps: KeymapProviding
    private let settings: SettingsStore

    public init(inputSource: InputSourceServicing,
                textSelection: TextSelectionServicing,
                keymaps: KeymapProviding,
                settings: SettingsStore) {
        self.inputSource = inputSource
        self.textSelection = textSelection
        self.keymaps = keymaps
        self.settings = settings
    }

    public func switchAndTranslate() {
        debugLog("switchAndTranslate enter") // TEMPORARY DEBUG
        guard let currentID = inputSource.currentLayoutID() else {
            logError("could not determine current input source")
            return
        }

        let enabled = resolvedEnabledSourceIDs()
        debugLog("current=\(currentID) enabled=\(enabled.count) \(enabled)") // TEMPORARY DEBUG
        guard enabled.count >= 2 else { return }

        // Current layout not in the enabled list → target the first enabled one (spec §3.1).
        let targetID: String
        if let index = enabled.firstIndex(of: currentID) {
            targetID = enabled[(index + 1) % enabled.count]
        } else {
            targetID = enabled[0]
        }

        // AX read first; apps that don't expose the selection via AX (Electron/Chromium)
        // are read via the clipboard dance (spec §3.4 read fallback).
        guard let text = textSelection.selectedText() ?? textSelection.selectedTextViaClipboard(),
              !text.isEmpty else {
            debugLog("no text captured via AX or clipboard") // TEMPORARY DEBUG
            return
        }
        debugLog("captured \(text.count) chars: \(text.prefix(40))") // TEMPORARY DEBUG
        guard let sourceKeymap = keymaps.keymap(forSourceID: currentID),
              let targetKeymap = keymaps.keymap(forSourceID: targetID) else {
            logError("no keymap for \(currentID) or \(targetID)")
            return
        }

        let translated = KeymapTranslator.translate(text, source: sourceKeymap, target: targetKeymap)
        debugLog("translated -> \(translated.prefix(40))") // TEMPORARY DEBUG
        let replaced = textSelection.replaceSelectedText(with: translated)
        debugLog("replace result: \(replaced)") // TEMPORARY DEBUG
        if !replaced {
            logError("could not replace selection")
        }
        let switched = inputSource.selectLayout(id: targetID)
        debugLog("switch to \(targetID): \(switched)") // TEMPORARY DEBUG
        if !switched {
            logError("could not switch input source to \(targetID)")
        }
    }

    /// Enabled layout IDs: saved settings minus IDs no longer present in the system;
    /// empty (first launch or all stale) → all system layouts (spec §4.1).
    func resolvedEnabledSourceIDs() -> [String] {
        let systemIDs = inputSource.enabledLayouts().map(\.id)
        let saved = settings.load().enabledSourceIDs.filter { systemIDs.contains($0) }
        return saved.isEmpty ? systemIDs : saved
    }
}
