package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.data.local.RecipeIngredient
import java.util.UUID

/**
 * Presentation-facing logic for the Recipe Browser (Phase 9) — a Kotlin port of iOS's
 * `RecipePresentation.swift`, kept out of Composables so it stays unit-testable and both
 * platforms apply identical rules (see NORSE_MIXOLOGY_BUILD.md's "Recipe Browser rules").
 */

/**
 * Match results partitioned into the three sections the Recipe Browser shows. Order within each
 * group is the engine's order (exact first, then score descending), which this never re-sorts.
 */
data class GroupedMatchResults(
    /** `matchType == Exact` — the cabinet covers every required ingredient. */
    val perfect: List<RecipeMatchResult>,
    /** Partial matches needing at most one substitution. */
    val almost: List<RecipeMatchResult>,
    /** Partial matches needing two or more substitutions. */
    val exploring: List<RecipeMatchResult>,
) {
    val isEmpty: Boolean get() = perfect.isEmpty() && almost.isEmpty() && exploring.isEmpty()

    companion object {
        val Empty = GroupedMatchResults(emptyList(), emptyList(), emptyList())

        fun from(results: List<RecipeMatchResult>): GroupedMatchResults {
            val perfect = mutableListOf<RecipeMatchResult>()
            val almost = mutableListOf<RecipeMatchResult>()
            val exploring = mutableListOf<RecipeMatchResult>()
            for (result in results) {
                when {
                    result.matchType == MatchType.Exact -> perfect += result
                    result.substitutions.size <= 1 -> almost += result
                    else -> exploring += result
                }
            }
            return GroupedMatchResults(perfect, almost, exploring)
        }
    }
}

/**
 * What a recipe card's match badge should communicate. Results never include recipes with
 * unresolved required ingredients, so a card is either fully covered or needs substitutions.
 */
sealed interface MatchBadgeState {
    data object Exact : MatchBadgeState
    data class Substituted(val count: Int) : MatchBadgeState

    companion object {
        fun of(result: RecipeMatchResult): MatchBadgeState = when (result.matchType) {
            MatchType.Exact -> Exact
            MatchType.Partial -> Substituted(maxOf(1, result.substitutions.size))
        }
    }
}

enum class AvailabilityStatus {
    /** The exact ingredient is in the cabinet. */
    Exact,

    /** A different ingredient from the cabinet stands in for it. */
    Substituted,

    /**
     * Not in the cabinet and not substituted. Only optional/garnish ingredients can end up here —
     * a missing required ingredient drops the recipe from the results entirely.
     */
    Unavailable,
}

/** One recipe ingredient line plus how the user's cabinet covers it. */
data class IngredientAvailability(
    /** Position in the recipe's ingredient list — unique even if a recipe lists the same style twice. */
    val id: Int,
    val ingredient: RecipeIngredient,
    val status: AvailabilityStatus,
    val substitution: SubstitutionDetail?,
)

object RecipeAvailability {
    /** Resolves each ingredient of a matched recipe against the cabinet, in recipe order. */
    fun rows(result: RecipeMatchResult, cabinetStyleIds: Set<UUID>): List<IngredientAvailability> =
        rows(result.ingredients, result.substitutions, cabinetStyleIds)

    /**
     * For a recipe without a match result — e.g. a favourite the current cabinet can't make —
     * pass no substitutions: every ingredient is then simply in the cabinet or not.
     *
     * A reported substitution wins over an exact style in the cabinet, because a user "accept"
     * override can substitute even when the exact style is also owned.
     */
    fun rows(
        ingredients: List<RecipeIngredient>,
        substitutions: List<SubstitutionDetail>,
        cabinetStyleIds: Set<UUID>,
    ): List<IngredientAvailability> {
        val substitutionByRequiredId = substitutions.associateBy { it.required.id }
        return ingredients.mapIndexed { position, ingredient ->
            val substitution = substitutionByRequiredId[ingredient.ingredientStyleId]
            if (substitution != null) {
                IngredientAvailability(position, ingredient, AvailabilityStatus.Substituted, substitution)
            } else {
                val status = if (ingredient.ingredientStyleId in cabinetStyleIds) AvailabilityStatus.Exact else AvailabilityStatus.Unavailable
                IngredientAvailability(position, ingredient, status, null)
            }
        }
    }
}
