import Foundation

/// Parses a leading `"<number>ml"` amount into millilitres, used only to
/// pick the "base" spirit among several in a recipe (see `RoleDerivation`).
/// Amounts that aren't `ml`-denominated (dashes, "top", garnish counts)
/// return `nil` and are never treated as the base.
enum AmountParsing {
    static func milliliters(from amount: String) -> Double? {
        guard let range = amount.range(of: #"^\s*[0-9]+(\.[0-9]+)?\s*ml"#, options: .regularExpression) else {
            return nil
        }
        let numeric = amount[range].trimmingCharacters(in: .letters).trimmingCharacters(in: .whitespaces)
        return Double(numeric)
    }
}

/// Derives each `RecipeIngredient`'s functional role from its taxonomy
/// category/family, since `RecipeIngredient` itself has no role field.
/// Both platforms must apply this exact derivation (see Phase 3 notes).
public enum RoleDerivation {
    public static func role(for ingredient: RecipeIngredient, style: IngredientStyle, in recipe: Recipe, index: TaxonomyIndex) -> IngredientRole {
        let categoryName = index.categoryName(for: style)
        let familyName = index.familyName(for: style)

        switch categoryName {
        case "Spirit":
            guard let myMl = AmountParsing.milliliters(from: ingredient.amount) else { return .modifier }
            let otherSpiritMl = recipe.ingredients.compactMap { other -> Double? in
                guard let otherStyle = index.stylesById[other.ingredientStyleId],
                      index.categoryName(for: otherStyle) == "Spirit" else { return nil }
                return AmountParsing.milliliters(from: other.amount)
            }
            let maxMl = otherSpiritMl.max() ?? myMl
            return myMl >= maxMl ? .base : .modifier
        case "Wine & Fortified":
            return .modifier
        case "Liqueur":
            return .accent
        case "Syrup":
            return .sweetenerSour
        case "Mixer":
            return familyName == "Juice" ? .sweetenerSour : .bittersMixer
        case "Garnish":
            return familyName == "Bitters" ? .bittersMixer : .garnish
        case "Fruit":
            return .garnish
        default:
            return .accent
        }
    }
}

/// The on-device recipe matching engine — the single source of truth for
/// both platforms (see Data Model.md "Matching Score & Strictness"; the
/// Android port in Phase 8 must reproduce this exactly).
public enum MatchingService {
    enum Resolution {
        case unresolved
        /// `substituteStyle` is nil for an exact match (nothing to report);
        /// non-nil (and different from the required style) for a real substitution.
        case resolved(quality: Double, substituteStyle: IngredientStyle?)
    }

    public static func match(
        cabinet: [CabinetItem],
        recipes: [Recipe],
        index: TaxonomyIndex,
        prefs: MatchPreferences = .default
    ) -> [RecipeMatchResult] {
        guard !cabinet.isEmpty else { return [] }

        let cabinetByStyleId = Dictionary(cabinet.map { ($0.ingredientStyleId, $0) }, uniquingKeysWith: { first, _ in first })
        var cabinetByFamilyId: [UUID: [CabinetItem]] = [:]
        for item in cabinet {
            cabinetByFamilyId[item.ingredientFamilyId, default: []].append(item)
        }
        let curatedTable = CuratedSubstitutions.table(index: index)

        var results: [RecipeMatchResult] = []

        recipeLoop: for recipe in recipes {
            var totalWeight = 0.0
            var weightedShortfall = 0.0
            var substitutions: [SubstitutionDetail] = []

            for ingredient in recipe.ingredients {
                guard let requiredStyle = index.stylesById[ingredient.ingredientStyleId] else {
                    continue // dangling reference — validated away in Phase 1, never expected here
                }

                let role = RoleDerivation.role(for: ingredient, style: requiredStyle, in: recipe, index: index)
                // Garnishes are always skippable in practice (see Phase 3 notes) — treated
                // like an optional ingredient regardless of the seed data's isOptional flag.
                let isSoft = ingredient.isOptional || role == .garnish

                let resolution = resolve(
                    requiredStyle: requiredStyle,
                    cabinetByStyleId: cabinetByStyleId,
                    cabinetByFamilyId: cabinetByFamilyId,
                    stylesById: index.stylesById,
                    curatedTable: curatedTable,
                    prefs: prefs
                )

                switch resolution {
                case .unresolved:
                    if !isSoft { continue recipeLoop } // drop the recipe
                case .resolved(let quality, let substituteStyle):
                    let weight = prefs.weight(for: role)
                    totalWeight += weight
                    weightedShortfall += weight * (1 - quality)
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

            let matchScore = totalWeight > 0 ? 1 - (weightedShortfall / totalWeight) : 1.0
            let matchType: MatchType = matchScore >= 0.999 ? .exact : .partial
            results.append(RecipeMatchResult(recipe: recipe, matchScore: matchScore, matchType: matchType, substitutions: substitutions))
        }

        results.sort { lhs, rhs in
            if lhs.matchType != rhs.matchType { return lhs.matchType == .exact }
            return lhs.matchScore > rhs.matchScore
        }
        return results
    }

    /// Internal (not private) so `CatalogAvailability` reuses the exact same per-ingredient rule.
    static func resolve(
        requiredStyle: IngredientStyle,
        cabinetByStyleId: [UUID: CabinetItem],
        cabinetByFamilyId: [UUID: [CabinetItem]],
        stylesById: [UUID: IngredientStyle],
        curatedTable: [UUID: [(substituteId: UUID, baseQuality: Double)]],
        prefs: MatchPreferences
    ) -> Resolution {
        // 1. User accept override.
        // A style that has left the catalog can't be a substitute (see CatalogToleranceTests).
        if let acceptedId = prefs.acceptOverrides[requiredStyle.id],
           !prefs.isRejected(substituteId: acceptedId, for: requiredStyle.id),
           cabinetByStyleId[acceptedId] != nil,
           let acceptedStyle = stylesById[acceptedId] {
            return .resolved(quality: 1.0, substituteStyle: acceptedStyle)
        }

        // 2. Exact style in cabinet.
        if cabinetByStyleId[requiredStyle.id] != nil, !prefs.isRejected(substituteId: requiredStyle.id, for: requiredStyle.id) {
            return .resolved(quality: 1.0, substituteStyle: nil)
        }

        // 3. Curated Tier 3 rule.
        if let candidates = curatedTable[requiredStyle.id] {
            for candidate in candidates
            where !prefs.isRejected(substituteId: candidate.substituteId, for: requiredStyle.id)
                && cabinetByStyleId[candidate.substituteId] != nil {
                return .resolved(quality: candidate.baseQuality, substituteStyle: stylesById[candidate.substituteId])
            }
        }

        // 4. Best same-family cabinet item by cosine similarity.
        let familyCandidates = (cabinetByFamilyId[requiredStyle.familyId] ?? [])
            .filter {
                $0.ingredientStyleId != requiredStyle.id
                    && stylesById[$0.ingredientStyleId] != nil // ghost cabinet items never substitute
                    && !prefs.isRejected(substituteId: $0.ingredientStyleId, for: requiredStyle.id)
            }

        var best: (item: CabinetItem, similarity: Double)?
        for candidate in familyCandidates {
            let similarity = FlavorSimilarity.cosine(requiredStyle.flavorProfile, candidate.flavorProfile)
            if similarity > (best?.similarity ?? -1) {
                best = (candidate, similarity)
            }
        }
        if let best, best.similarity >= prefs.similarityThreshold {
            return .resolved(quality: best.similarity, substituteStyle: stylesById[best.item.ingredientStyleId])
        }

        return .unresolved
    }
}
