import Foundation

/// Evaluates every catalog recipe against the cabinet — the All recipes view.
/// "Ready" is the matching engine's own result; for everything else the
/// engine's per-ingredient `resolve` decides what is missing, so the two views
/// can never disagree. Additive only: `MatchingService` is not changed.
public enum CatalogAvailability {
    public static func evaluate(
        recipes: [Recipe],
        cabinet: [CabinetItem],
        taxonomyCategories: [IngredientCategory],
        prefs: MatchPreferences = .default
    ) -> [CatalogEntry] {
        evaluate(recipes: recipes, cabinet: cabinet, index: TaxonomyIndex(categories: taxonomyCategories), prefs: prefs)
    }

    public static func evaluate(
        recipes: [Recipe],
        cabinet: [CabinetItem],
        index: TaxonomyIndex,
        prefs: MatchPreferences = .default
    ) -> [CatalogEntry] {
        let matches = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index, prefs: prefs)
        let matchById = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The same lookups `MatchingService.match` builds — duplicated rather than
        // refactored out so the engine itself stays untouched.
        let cabinetByStyleId = Dictionary(cabinet.map { ($0.ingredientStyleId, $0) }, uniquingKeysWith: { first, _ in first })
        var cabinetByFamilyId: [UUID: [CabinetItem]] = [:]
        for item in cabinet {
            cabinetByFamilyId[item.ingredientFamilyId, default: []].append(item)
        }
        let curatedTable = CuratedSubstitutions.table(index: index)

        return recipes.map { recipe in
            if let match = matchById[recipe.id] {
                return CatalogEntry(recipe: recipe, match: match, substitutions: match.substitutions, missing: [])
            }

            var substitutions: [SubstitutionDetail] = []
            var missing: [IngredientStyle] = []
            for ingredient in recipe.ingredients {
                guard let requiredStyle = index.stylesById[ingredient.ingredientStyleId] else {
                    continue // dangling reference — skipped exactly as the engine does
                }
                let role = RoleDerivation.role(for: ingredient, style: requiredStyle, in: recipe, index: index)
                let isSoft = ingredient.isOptional || role == .garnish

                let resolution = MatchingService.resolve(
                    requiredStyle: requiredStyle,
                    cabinetByStyleId: cabinetByStyleId,
                    cabinetByFamilyId: cabinetByFamilyId,
                    stylesById: index.stylesById,
                    curatedTable: curatedTable,
                    prefs: prefs
                )
                switch resolution {
                case .unresolved:
                    if !isSoft, !missing.contains(where: { $0.id == requiredStyle.id }) {
                        missing.append(requiredStyle)
                    }
                case .resolved(let quality, let substituteStyle):
                    if let substituteStyle, substituteStyle.id != requiredStyle.id {
                        substitutions.append(SubstitutionDetail(
                            required: requiredStyle,
                            substitute: substituteStyle,
                            similarityScore: quality,
                            note: SubstitutionNote.generate(required: requiredStyle, substitute: substituteStyle),
                            ratioHint: SubstitutionNote.ratioHint(role: role, required: requiredStyle, substitute: substituteStyle)
                        ))
                    }
                }
            }

            // The engine returns nothing for an empty cabinet, so an unmatched
            // recipe with nothing missing is only expected then.
            if missing.isEmpty, !cabinet.isEmpty {
                AppLog.catalog.fault("Recipe \(recipe.name, privacy: .public) is not makeable but has nothing missing")
            }
            return CatalogEntry(recipe: recipe, match: nil, substitutions: substitutions, missing: missing)
        }
    }
}
