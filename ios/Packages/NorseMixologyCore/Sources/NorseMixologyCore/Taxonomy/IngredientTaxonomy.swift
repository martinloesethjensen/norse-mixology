import Foundation

/// Parses the bundled `taxonomy.json` / `recipes.json` into models.
///
/// Deliberately takes raw `Data` rather than reaching for `Bundle.main` —
/// that keeps this pure and testable, and lets the app target (which owns
/// the actual bundled JSON under `NorseMixology/Resources/`) decide where
/// the bytes come from. No matching/substitution logic here — see the
/// matching engine (Phase 3).
public enum IngredientTaxonomy {
    public static func loadCategories(from data: Data) throws -> [IngredientCategory] {
        try JSONDecoder().decode([IngredientCategory].self, from: data)
    }

    public static func loadRecipes(from data: Data) throws -> [Recipe] {
        try JSONDecoder().decode([Recipe].self, from: data)
    }

    /// Flattens a parsed taxonomy into its leaf styles, keyed by id — the
    /// shape callers (matching engine, cabinet search) actually need.
    public static func flattenStyles(_ categories: [IngredientCategory]) -> [UUID: IngredientStyle] {
        var result: [UUID: IngredientStyle] = [:]
        for category in categories {
            for family in category.families {
                for style in family.styles {
                    result[style.id] = style
                }
            }
        }
        return result
    }
}
