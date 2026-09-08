import AppKit
import ApplicationServices
import SwiftUI
import KeyboardSwitcherCore

struct SettingsView: View {
    let store: SettingsStore
    let inputSource: InputSourceServicing

    @State private var layouts: [InputSourceInfo] = []
    @State private var enabledIDs: Set<String> = []
    @State private var accessibilityGranted = true

    var body: some View {
        Form {
            Section {
                if layouts.isEmpty {
                    Text("No keyboard layouts found").foregroundStyle(.secondary)
                }
                ForEach(layouts, id: \.id) { layout in
                    Toggle(isOn: binding(for: layout.id)) {
                        Text(layout.localizedName)
                    }
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("Checked languages participate in the option-command-K cycle.")
            }

            Section("Hotkey") {
                HStack {
                    Text("Translate & switch")
                    Spacer()
                    Text("⌥⌘K").foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear(perform: reload)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabledIDs.contains(id) },
            set: { isOn in
                if isOn {
                    enabledIDs.insert(id)
                } else {
                    enabledIDs.remove(id)
                }
                persist()
            }
        )
    }

    private func reload() {
        layouts = inputSource.enabledLayouts()
        let systemIDs = Set(layouts.map(\.id))
        let saved = store.load().enabledSourceIDs.filter { systemIDs.contains($0) }
        enabledIDs = saved.isEmpty ? systemIDs : Set(saved)
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func persist() {
        let ordered = layouts.filter { enabledIDs.contains($0.id) }.map(\.id)
        store.save(AppSettings(enabledSourceIDs: ordered))
    }
}
