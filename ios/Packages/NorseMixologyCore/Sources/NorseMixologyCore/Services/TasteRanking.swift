import Foundation

/// Re-ranks an already-computed `GroupedMatchResults` by how closely each
/// recipe's flavour matches the user's `UserTasteProfile` — a secondary sort
/// within each tier, never a change to `matchScore`/`matchType`/tier
/// membership (see `Data Model.md` "Matching Score & Strictness", which this
/// type must never touch).
public enum TasteRanking {
    /// Cosine similarity over only the 5 quizzed axes. Deliberately does not
    /// reuse `FlavorSimilarity.cosine` — that compares all 9 `FlavorProfile`
    /// dimensions, which would let un-quizzed axes (floral, spice, fruity,
    /// oaky) bias the result.
    public static func similarity(_ profile: UserTasteProfile, to flavor: FlavorProfile) -> Double {
        let pairs: [(Double, Double)] = [
            (profile.sweetness, flavor.sweetness),
            (profile.bitterness, flavor.bitterness),
            (profile.citrus, flavor.citrus),
            (profile.smokiness, flavor.smokiness),
            (profile.herbal, flavor.herbal),
        ]
        let dot = pairs.reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = (pairs.reduce(0.0) { $0 + $1.0 * $1.0 }).squareRoot()
        let magB = (pairs.reduce(0.0) { $0 + $1.1 * $1.1 }).squareRoot()
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    /// A neutral (all axes still 0.5) or uncompleted profile never changes any order.
    public static func isActive(_ profile: UserTasteProfile) -> Bool {
        let hasNeutralAxes = profile.sweetness == 0.5 && profile.bitterness == 0.5
            && profile.citrus == 0.5 && profile.smokiness == 0.5 && profile.herbal == 0.5
        return profile.hasCompletedOnboarding && !hasNeutralAxes
    }

    /// Stable sort by taste similarity, most similar first; a no-op for an inactive profile.
    public static func sorted<T>(_ items: [T], toward profile: UserTasteProfile, flavor: (T) -> FlavorProfile) -> [T] {
        guard isActive(profile) else { return items }
        return items.sorted { similarity(profile, to: flavor($0)) > similarity(profile, to: flavor($1)) }
    }

    /// A neutral (all axes still 0.5) or uncompleted profile is a no-op —
    /// the original matchScore-descending order is preserved.
    public static func reorder(_ grouped: GroupedMatchResults, toward profile: UserTasteProfile) -> GroupedMatchResults {
        guard isActive(profile) else { return grouped }
        let byTaste = { (results: [RecipeMatchResult]) in sorted(results, toward: profile) { $0.recipe.flavorProfile } }
        return GroupedMatchResults(results: byTaste(grouped.perfect) + byTaste(grouped.almost) + byTaste(grouped.exploring))
    }
}
