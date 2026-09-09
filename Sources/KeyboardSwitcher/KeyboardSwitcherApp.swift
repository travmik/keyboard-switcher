import SwiftUI
import ApplicationServices
import KeyboardSwitcherCore

@main
struct KeyboardSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Keyboard Switcher", systemImage: "keyboard") {
            Button("Settings…") { appDelegate.showSettings() }
            Button("About Keyboard Switcher") { appDelegate.showAbout() }
            Divider()
            Button("Quit Keyboard Switcher") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: Orchestrator?
    private var hotkeyManager: HotkeyManager?
    private let menuController = MenuController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let inputSource = InputSourceService()
        let settings = SettingsStore()
        let textSelection = TextSelectionService(shouldRestoreClipboard: {
            settings.load().restoreClipboardAfterFix
        })
        let keymaps = KeymapProvider()
        orchestrator = Orchestrator(
            inputSource: inputSource,
            textSelection: textSelection,
            keymaps: keymaps,
            settings: settings
        )
        menuController.configure(settings: settings, inputSource: inputSource)

        let hotkey = HotkeyManager { [weak orchestrator] in
            orchestrator?.switchAndTranslate()
        }
        let installed = hotkey.install()
        if !installed {
            logError("failed to register hotkey option-command-K")
        }
        hotkeyManager = hotkey
        debugLog("startup: trusted=\(AXIsProcessTrusted()) installed=\(installed)") // TEMPORARY DEBUG
    }

    func showSettings() { menuController.showSettings() }
    func showAbout() { menuController.showAbout() }
}
