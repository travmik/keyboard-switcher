import Foundation

public struct AppSettings: Codable, Equatable {
    public var enabledSourceIDs: [String]
    /// Whether the ⌘V paste fallback puts the previous clipboard content back after
    /// pasting. Off by default: the translated text stays on the clipboard (spec §3.4).
    public var restoreClipboardAfterFix: Bool

    public init(enabledSourceIDs: [String] = [], restoreClipboardAfterFix: Bool = false) {
        self.enabledSourceIDs = enabledSourceIDs
        self.restoreClipboardAfterFix = restoreClipboardAfterFix
    }

    /// Tolerates settings written before `restoreClipboardAfterFix` existed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledSourceIDs = try container.decodeIfPresent([String].self, forKey: .enabledSourceIDs) ?? []
        restoreClipboardAfterFix = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboardAfterFix) ?? false
    }
}

/// Persists app settings as JSON in UserDefaults (spec §4.1).
public final class SettingsStore {
    private let defaults: UserDefaults
    private static let storageKey = "AppSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.storageKey) else { return AppSettings() }
        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
