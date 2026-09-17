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
}
