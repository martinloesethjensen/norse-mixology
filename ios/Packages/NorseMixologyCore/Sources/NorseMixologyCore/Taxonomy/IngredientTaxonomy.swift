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

    /// Skips individual malformed recipe entries rather than failing the whole
    /// catalog — one bad entry must never leave the app with no recipes.
    /// Still throws if the data isn't a JSON array at all.
    public static func loadRecipes(from data: Data) throws -> [Recipe] {
        try loadRecipesReportingSkipped(from: data).recipes
    }

    /// Like `loadRecipes`, also reporting how many entries could not be decoded
    /// (so the caller can log it).
    public static func loadRecipesReportingSkipped(from data: Data) throws -> (recipes: [Recipe], skippedCount: Int) {
        let entries = try JSONDecoder().decode([LossyDecodable<Recipe>].self, from: data)
        let recipes = entries.compactMap(\.value)
        return (recipes, entries.count - recipes.count)
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

/// Decodes to `nil` instead of throwing, so one bad element doesn't fail the
/// whole array it sits in. (The array's container still advances past it.)
private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
