import Foundation

public struct AppSettings: Codable, Equatable {
    public var enabledSourceIDs: [String]

    public init(enabledSourceIDs: [String] = []) {
        self.enabledSourceIDs = enabledSourceIDs
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
