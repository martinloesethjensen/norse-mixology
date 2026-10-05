import Foundation

/// One "buy next" bottle and what it would do for the user.
public struct BuyNextSuggestion: Identifiable, Equatable, Sendable {
    public let style: IngredientStyle
    /// Recipes whose ONLY missing ingredient is this style — Ready the moment it's owned.
    public let readyNow: Int
    /// Recipes missing this style plus at least one other.
    public let movesCloser: Int
    /// The ready-now recipes, best taste fit first (by name for a neutral profile).
    public let readyNowRecipeNames: [String]

    public var id: UUID { style.id }
}

/// Ranks the bottles that would unlock the most recipes (Shopping List spec §2).
/// Reads `CatalogEntry.missing` only — never re-runs the matching engine.
public enum BuyNextRanking {
    public static func rank(
        entries: [CatalogEntry],
        listedStyleIds: Set<UUID>,
        profile: UserTasteProfile,
        limit: Int = 5
    ) -> [BuyNextSuggestion] {
        struct Tally {
            let style: IngredientStyle
            var readyNow: [(name: String, fit: Double)] = []
            var movesCloser = 0
            var fit = 0.0
        }

        let tasteIsActive = TasteRanking.isActive(profile)
        var tallies: [UUID: Tally] = [:]
        for entry in entries where entry.match == nil && !entry.missing.isEmpty {
            let fit = tasteIsActive ? TasteRanking.similarity(profile, to: entry.recipe.flavorProfile) : 0
            for style in entry.missing where !listedStyleIds.contains(style.id) {
                var tally = tallies[style.id] ?? Tally(style: style)
                if entry.missing.count == 1 {
                    tally.readyNow.append((entry.recipe.name, fit))
                } else {
                    tally.movesCloser += 1
                }
                tally.fit += fit
                tallies[style.id] = tally
            }
        }

        let ranked = tallies.values.sorted { lhs, rhs in
            if lhs.readyNow.count != rhs.readyNow.count { return lhs.readyNow.count > rhs.readyNow.count }
            if lhs.movesCloser != rhs.movesCloser { return lhs.movesCloser > rhs.movesCloser }
            if lhs.fit != rhs.fit { return lhs.fit > rhs.fit }
            let byName = lhs.style.name.localizedStandardCompare(rhs.style.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.style.id.uuidString < rhs.style.id.uuidString // deterministic for duplicate names
        }

        return ranked.prefix(max(limit, 0)).map { tally in
            let names = tally.readyNow
                .sorted { lhs, rhs in
                    lhs.fit != rhs.fit ? lhs.fit > rhs.fit : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                .map(\.name)
            return BuyNextSuggestion(style: tally.style, readyNow: tally.readyNow.count,
                                     movesCloser: tally.movesCloser, readyNowRecipeNames: names)
        }
    }
}
