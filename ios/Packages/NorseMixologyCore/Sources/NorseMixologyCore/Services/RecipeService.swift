import Foundation

/// Runs the matching engine against the bundled recipe catalog loaded in
/// Phase 1 — entirely on-device, no network round-trip.
public enum RecipeService {
    public static func findRecipes(
        for cabinet: [CabinetItem],
        recipes: [Recipe],
        taxonomyCategories: [IngredientCategory],
        prefs: MatchPreferences = .default
    ) -> [RecipeMatchResult] {
        MatchingService.match(cabinet: cabinet, recipes: recipes, index: TaxonomyIndex(categories: taxonomyCategories), prefs: prefs)
    }

    /// Matches a single recipe against the cabinet — `nil` when the cabinet
    /// can't make it (an unresolved required ingredient), which is how a
    /// favourite that is no longer makeable shows up.
    public static func matchResult(
        for recipe: Recipe,
        cabinet: [CabinetItem],
        taxonomyCategories: [IngredientCategory],
        prefs: MatchPreferences = .default
    ) -> RecipeMatchResult? {
        findRecipes(for: cabinet, recipes: [recipe], taxonomyCategories: taxonomyCategories, prefs: prefs).first
    }
}
