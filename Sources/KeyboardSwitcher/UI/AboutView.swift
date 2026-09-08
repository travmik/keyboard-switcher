import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Keyboard Switcher")
                .font(.title2.bold())
            Text(versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Fixes text typed in the wrong keyboard layout.\nSelect the text and press ⌥⌘K.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 300, height: 180)
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "Version \(version)"
    }
}
