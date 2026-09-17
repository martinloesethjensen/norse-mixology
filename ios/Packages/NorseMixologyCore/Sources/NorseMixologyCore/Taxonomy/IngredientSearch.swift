import Foundation

/// Free-text search across the taxonomy, used by `AddIngredientView`.
public enum IngredientSearch {
    /// Case-insensitive substring match on style name, family name, or any
    /// example brand. Empty/whitespace-only queries return no results.
    public static func search(_ query: String, in categories: [IngredientCategory]) -> [IngredientStyle] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()

        var results: [IngredientStyle] = []
        for category in categories {
            for family in category.families {
                let familyMatches = family.name.lowercased().contains(q)
                for style in family.styles {
                    let styleMatches = style.name.lowercased().contains(q)
                    let brandMatches = style.exampleBrands.contains { $0.lowercased().contains(q) }
                    if familyMatches || styleMatches || brandMatches {
                        results.append(style)
                    }
                }
            }
        }
        return results
    }
}
