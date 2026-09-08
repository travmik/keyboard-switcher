import AppKit
import SwiftUI
import KeyboardSwitcherCore

/// Owns the Settings and About windows, hosting SwiftUI views in AppKit windows
/// (spec §4: avoids SwiftUI window-lifecycle quirks inside MenuBarExtra-only apps).
@MainActor
final class MenuController {
    private var settingsStore: SettingsStore?
    private var inputSourceService: InputSourceServicing?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    func configure(settings: SettingsStore, inputSource: InputSourceServicing) {
        settingsStore = settings
        inputSourceService = inputSource
    }

    func showSettings() {
        guard let settingsStore, let inputSourceService else { return }
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Keyboard Switcher — Settings"
            window.contentView = NSHostingView(
                rootView: SettingsView(store: settingsStore, inputSource: inputSourceService)
            )
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        let window: NSWindow
        if let existing = aboutWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 180),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "About Keyboard Switcher"
            window.contentView = NSHostingView(rootView: AboutView())
            window.center()
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
