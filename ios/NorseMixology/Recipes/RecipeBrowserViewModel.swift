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
        results = RecipeService.findRecipes(
            for: cabinet,
            recipes: taxonomyStore.recipes,
            taxonomyCategories: taxonomyStore.categories
        )
        grouped = GroupedMatchResults(results: results)
        cabinetStyleIds = Set(cabinet.map(\.ingredientStyleId))

        // A recipe can drop out of the results when the cabinet changes.
        if let selectedRecipeID, !results.contains(where: { $0.id == selectedRecipeID }) {
            self.selectedRecipeID = nil
        }
    }
}
