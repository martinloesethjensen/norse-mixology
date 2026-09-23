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

    /// A neutral (all axes still 0.5) or uncompleted profile is a no-op —
    /// the original matchScore-descending order is preserved.
    public static func reorder(_ grouped: GroupedMatchResults, toward profile: UserTasteProfile) -> GroupedMatchResults {
        let hasNeutralAxes = profile.sweetness == 0.5 && profile.bitterness == 0.5
            && profile.citrus == 0.5 && profile.smokiness == 0.5 && profile.herbal == 0.5
        guard profile.hasCompletedOnboarding, !hasNeutralAxes else { return grouped }

        func sortedByTaste(_ results: [RecipeMatchResult]) -> [RecipeMatchResult] {
            results.sorted {
                similarity(profile, to: $0.recipe.flavorProfile) > similarity(profile, to: $1.recipe.flavorProfile)
            }
        }

        return GroupedMatchResults(
            results: sortedByTaste(grouped.perfect) + sortedByTaste(grouped.almost) + sortedByTaste(grouped.exploring)
        )
    }
}
