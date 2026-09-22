package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.data.local.CabinetItem
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.data.local.RecipeIngredient
import dev.martinloeseth.norsemixology.domain.RecipeWithIngredients
import dev.martinloeseth.norsemixology.domain.Taxonomy
import java.util.UUID

/**
 * Parses a leading "<number>ml" amount into millilitres, used only to pick the "base" spirit
 * among several in a recipe (see [RoleDerivation]). Amounts that aren't ml-denominated (dashes,
 * "top", garnish counts) return null and are never treated as the base.
 */
private object AmountParsing {
    private val mlPrefix = Regex("""^\s*[0-9]+(\.[0-9]+)?\s*ml""")

    fun milliliters(amount: String): Double? {
        val match = mlPrefix.find(amount) ?: return null
        val numeric = match.value.trimEnd { it.isLetter() || it.isWhitespace() }
        return numeric.toDoubleOrNull()
    }
}

/**
 * Derives each [RecipeIngredient]'s functional role from its taxonomy category/family, since
 * `RecipeIngredient` itself has no role field. Both platforms must apply this exact derivation
 * (see Phase 3 notes) — kept in lockstep with iOS's `RoleDerivation`.
 */
object RoleDerivation {
    fun role(ingredient: RecipeIngredient, style: IngredientStyle, recipeIngredients: List<RecipeIngredient>, taxonomy: Taxonomy): IngredientRole {
        val categoryName = taxonomy.categoryNamesById[style.categoryId] ?: ""
        val familyName = taxonomy.familyNamesById[style.familyId] ?: ""

        return when (categoryName) {
            "Spirit" -> {
                val myMl = AmountParsing.milliliters(ingredient.amount) ?: return IngredientRole.Modifier
                val otherSpiritMl = recipeIngredients.mapNotNull { other ->
                    val otherStyle = taxonomy.stylesById[other.ingredientStyleId] ?: return@mapNotNull null
                    if ((taxonomy.categoryNamesById[otherStyle.categoryId] ?: "") != "Spirit") return@mapNotNull null
                    AmountParsing.milliliters(other.amount)
                }
                val maxMl = otherSpiritMl.maxOrNull() ?: myMl
                if (myMl >= maxMl) IngredientRole.Base else IngredientRole.Modifier
            }
            "Wine & Fortified" -> IngredientRole.Modifier
            "Liqueur" -> IngredientRole.Accent
            "Syrup" -> IngredientRole.SweetenerSour
            "Mixer" -> if (familyName == "Juice") IngredientRole.SweetenerSour else IngredientRole.BittersMixer
            "Garnish" -> if (familyName == "Bitters") IngredientRole.BittersMixer else IngredientRole.Garnish
            "Fruit" -> IngredientRole.Garnish
            else -> IngredientRole.Accent
        }
    }
}

/**
 * The on-device recipe matching engine — a Kotlin port of iOS's `MatchingService`, which is the
 * single source of truth for both platforms (see Data Model.md "Matching Score & Strictness").
 * Must reproduce the Swift implementation's output exactly.
 */
object MatchingEngine {
    private sealed interface Resolution {
        data object Unresolved : Resolution
        /** [substituteStyle] is null for an exact match; non-null (and different from the
         *  required style) for a real substitution. */
        data class Resolved(val quality: Double, val substituteStyle: IngredientStyle?) : Resolution
    }

    fun match(
        cabinet: List<CabinetItem>,
        catalog: List<RecipeWithIngredients>,
        taxonomy: Taxonomy,
        prefs: MatchPreferences = MatchPreferences.Default,
    ): List<RecipeMatchResult> {
        if (cabinet.isEmpty()) return emptyList()

        val cabinetByStyleId = cabinet.associateBy { it.ingredientStyleId }
        val cabinetByFamilyId = cabinet.groupBy { it.ingredientFamilyId }
        val curatedTable = CuratedSubstitutions.table(taxonomy)

        val results = mutableListOf<RecipeMatchResult>()

        recipeLoop@ for (entry in catalog) {
            var totalWeight = 0.0
            var weightedShortfall = 0.0
            val substitutions = mutableListOf<SubstitutionDetail>()

            for (ingredient in entry.ingredients) {
                val requiredStyle = taxonomy.stylesById[ingredient.ingredientStyleId] ?: continue

                val role = RoleDerivation.role(ingredient, requiredStyle, entry.ingredients, taxonomy)
                // Garnishes are always skippable in practice (see Phase 3 notes) — treated like
                // an optional ingredient regardless of the seed data's isOptional flag.
                val isSoft = ingredient.isOptional || role == IngredientRole.Garnish

                when (val resolution = resolve(requiredStyle, cabinetByStyleId, cabinetByFamilyId, taxonomy.stylesById, curatedTable, prefs)) {
                    is Resolution.Unresolved -> {
                        if (!isSoft) continue@recipeLoop
                    }
                    is Resolution.Resolved -> {
                        val weight = prefs.weight(role)
                        totalWeight += weight
                        weightedShortfall += weight * (1 - resolution.quality)
                        val substituteStyle = resolution.substituteStyle
                        if (substituteStyle != null && substituteStyle.id != requiredStyle.id) {
                            substitutions.add(
                                SubstitutionDetail(
                                    required = requiredStyle,
                                    substitute = substituteStyle,
                                    similarityScore = resolution.quality,
                                    note = SubstitutionNote.generate(requiredStyle, substituteStyle),
                                    ratioHint = SubstitutionNote.ratioHint(role, requiredStyle, substituteStyle),
                                ),
                            )
                        }
                    }
                }
            }

            val matchScore = if (totalWeight > 0) 1 - (weightedShortfall / totalWeight) else 1.0
            val matchType = if (matchScore >= 0.999) MatchType.Exact else MatchType.Partial
            results.add(RecipeMatchResult(entry.recipe, entry.ingredients, matchScore, matchType, substitutions))
        }

        return results.sortedWith(
            compareByDescending<RecipeMatchResult> { it.matchType == MatchType.Exact }
                .thenByDescending { it.matchScore },
        )
    }

    private fun resolve(
        requiredStyle: IngredientStyle,
        cabinetByStyleId: Map<UUID, CabinetItem>,
        cabinetByFamilyId: Map<UUID, List<CabinetItem>>,
        stylesById: Map<UUID, IngredientStyle>,
        curatedTable: Map<UUID, List<Pair<UUID, Double>>>,
        prefs: MatchPreferences,
    ): Resolution {
        // 1. User accept override.
        val accepted = prefs.acceptOverrides[requiredStyle.id]
        if (accepted != null && !prefs.isRejected(accepted, requiredStyle.id) && cabinetByStyleId[accepted] != null) {
            return Resolution.Resolved(1.0, stylesById[accepted])
        }

        // 2. Exact style in cabinet.
        if (cabinetByStyleId[requiredStyle.id] != null && !prefs.isRejected(requiredStyle.id, requiredStyle.id)) {
            return Resolution.Resolved(1.0, null)
        }

        // 3. Curated Tier 3 rule.
        curatedTable[requiredStyle.id]?.let { candidates ->
            for ((substituteId, baseQuality) in candidates) {
                if (!prefs.isRejected(substituteId, requiredStyle.id) && cabinetByStyleId[substituteId] != null) {
                    return Resolution.Resolved(baseQuality, stylesById[substituteId])
                }
            }
        }

        // 4. Best same-family cabinet item by cosine similarity.
        val familyCandidates = (cabinetByFamilyId[requiredStyle.familyId] ?: emptyList())
            .filter { it.ingredientStyleId != requiredStyle.id && !prefs.isRejected(it.ingredientStyleId, requiredStyle.id) }

        var best: Pair<CabinetItem, Double>? = null
        for (candidate in familyCandidates) {
            val similarity = FlavorSimilarity.cosine(requiredStyle.flavorProfile, candidate.flavorProfile)
            if (similarity > (best?.second ?: -1.0)) {
                best = candidate to similarity
            }
        }
        if (best != null && best.second >= prefs.similarityThreshold) {
            return Resolution.Resolved(best.second, stylesById[best.first.ingredientStyleId])
        }

        return Resolution.Unresolved
    }
}
