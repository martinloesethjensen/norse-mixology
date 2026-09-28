import Foundation
import SwiftData
import NorseMixologyCore

/// Holds the latest on-device match for the Recipes tab. Shared app-wide so
/// Cabinet's "Find Recipes" and the Recipes tab read the same results.
///
/// Matching ~150 bundled recipes is near-instant, so `refresh` is synchronous
/// and there is no loading state (see Phase 3 notes).
@Observable
final class RecipeBrowserViewModel {
    private(set) var results: [RecipeMatchResult] = []
    private(set) var grouped = GroupedMatchResults(results: [])
    /// Styles in the cabinet at the time of the last refresh — the detail
    /// screen uses these to tell "exact" from "unavailable" ingredients.
    private(set) var cabinetStyleIds: Set<UUID> = []
    /// Identifies one Recipe Browser result's reveal state — keyed by recipe id
    /// AND whether it was a Perfect Match at the time, so a recipe that moves
    /// from Almost There into Perfect Match (e.g. the user adds the exact
    /// ingredient they were substituting) is treated as a genuinely new reveal
    /// for the hero sweep, even though its id was already "seen" in the other tier.
    struct RevealKey: Hashable {
        let id: UUID
        let isExactMatch: Bool
    }

    /// Recipe IDs (plus tier) that have already played their entrance/hero
    /// animation — cleared only when the set of result IDs changes (a real
    /// re-match), not on every `refresh()` call.
    @ObservationIgnored private(set) var revealedResultKeys: Set<RevealKey> = []
    /// When the current reveal "wave" started — set whenever the result-id set
    /// actually changes. `RecipeCardView` uses this to only apply its staggered
    /// entrance delay to the initial screenful of a wave, not to cards revealed
    /// later purely by scrolling (see RecipeCardView's `effectiveRevealDelay`).
    @ObservationIgnored private(set) var revealWaveStartedAt: Date = .distantPast
    /// Drives the detail pane on regular-width (iPad) layouts.
    var selectedRecipeID: UUID?

    var perfectMatches: [RecipeMatchResult] { grouped.perfect }
    var almostMatches: [RecipeMatchResult] { grouped.almost }
    var explorationMatches: [RecipeMatchResult] { grouped.exploring }

    var selectedRecipe: RecipeMatchResult? {
        guard let selectedRecipeID else { return nil }
        return results.first { $0.id == selectedRecipeID }
    }

    /// Re-runs the match against the cabinet currently in SwiftData.
    func refresh(context: ModelContext, taxonomyStore: TaxonomyStore) {
        refresh(cabinet: CabinetService.allItems(context: context), taxonomyStore: taxonomyStore)
    }

    func refresh(cabinet: [CabinetItem], taxonomyStore: TaxonomyStore) {
        let newResults = RecipeService.findRecipes(
            for: cabinet,
            recipes: taxonomyStore.recipes,
            taxonomyCategories: taxonomyStore.categories
        )

        // Only a genuine change in which recipes matched should replay each
        // card's entrance/hero animation — revisiting the Recipes tab with an
        // unchanged cabinet must not re-animate cards already shown.
        if Set(newResults.map(\.id)) != Set(results.map(\.id)) {
            revealedResultKeys.removeAll()
            revealWaveStartedAt = Date()
        }

        results = newResults
        grouped = GroupedMatchResults(results: results)
        grouped = TasteRanking.reorder(grouped, toward: TasteProfileStore.load())
        cabinetStyleIds = Set(cabinet.map(\.ingredientStyleId))

        // A recipe can drop out of the results when the cabinet changes.
        if let selectedRecipeID, !results.contains(where: { $0.id == selectedRecipeID }) {
            self.selectedRecipeID = nil
        }
    }

    /// Whether `id` has already played its Recipe Browser entrance/hero
    /// animation this "generation" of results — see `refresh`'s id-set check.
    /// Used so `LazyVStack` recycling rows during scroll doesn't replay a
    /// card's fade-in or the Perfect Match sweep every time it scrolls back
    /// into view.
    func hasBeenRevealed(_ id: UUID, isExactMatch: Bool) -> Bool {
        revealedResultKeys.contains(RevealKey(id: id, isExactMatch: isExactMatch))
    }

    func markRevealed(_ id: UUID, isExactMatch: Bool) {
        revealedResultKeys.insert(RevealKey(id: id, isExactMatch: isExactMatch))
    }
}
