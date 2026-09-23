import Foundation

/// The user's flavour leanings on the 5 axes quizzed during onboarding
/// (see `Phases/Phase 11 - iOS Taste Profile & Animated Onboarding.md`).
/// Used only to break ties within an already-computed `GroupedMatchResults`
/// tier — never fed into `MatchingService`/`matchScore`.
///
/// Deliberately has no `floral`/`spice`/`fruity`/`oaky` fields: those axes
/// are never quizzed, so defaulting and comparing them would silently bias
/// ranking toward recipes that happen to sit near 0.5 on axes the user was
/// never asked about.
public struct UserTasteProfile: Codable, Equatable, Sendable {
    public var sweetness: Double
    public var bitterness: Double
    public var citrus: Double
    public var smokiness: Double
    public var herbal: Double
    public var hasCompletedOnboarding: Bool

    public init(
        sweetness: Double = 0.5,
        bitterness: Double = 0.5,
        citrus: Double = 0.5,
        smokiness: Double = 0.5,
        herbal: Double = 0.5,
        hasCompletedOnboarding: Bool = false
    ) {
        self.sweetness = sweetness
        self.bitterness = bitterness
        self.citrus = citrus
        self.smokiness = smokiness
        self.herbal = herbal
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// All axes at the midpoint, onboarding not completed — the value `load()`
    /// returns when nothing has been saved yet.
    public static let neutral = UserTasteProfile()
}
