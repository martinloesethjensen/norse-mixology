import Foundation

/// Persists the user's `UserTasteProfile` as a single JSON blob in
/// `UserDefaults`. `defaults` is an injected parameter (not hardcoded to
/// `.standard`) so tests can use `UserDefaults(suiteName:)` — the same
/// testability pattern as the app's other services.
public enum TasteProfileStore {
    private static let key = "com.norsemixology.userTasteProfile"

    public static func load(defaults: UserDefaults = .standard) -> UserTasteProfile {
        guard
            let data = defaults.data(forKey: key),
            let profile = try? JSONDecoder().decode(UserTasteProfile.self, from: data)
        else {
            return .neutral
        }
        return profile
    }

    public static func save(_ profile: UserTasteProfile, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }
}
