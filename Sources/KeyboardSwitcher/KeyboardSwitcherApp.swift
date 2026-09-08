import SwiftUI

@main
struct KeyboardSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra("Keyboard Switcher", systemImage: "keyboard") {
            Button("Quit Keyboard Switcher") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
