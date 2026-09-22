package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.data.local.Recipe
import dev.martinloeseth.norsemixology.data.local.RecipeIngredient
import java.util.UUID

/**
 * The functional role an ingredient plays within a recipe, used to weight its contribution to
 * `matchScore`. Not stored on `RecipeIngredient` — derived at match time by [RoleDerivation] from
 * the ingredient's taxonomy category/family and, for spirits, its amount relative to the recipe's
 * other spirits. See [RoleDerivation] for the exact derivation both platforms must replicate.
 */
enum class IngredientRole {
    Base, Modifier, SweetenerSour, BittersMixer, Accent, Garnish;

    /** Default weights from Data Model.md's "Matching Score & Strictness" spec. */
    val defaultWeight: Double
        get() = when (this) {
            Base -> 1.0
            Modifier -> 0.8
            SweetenerSour -> 0.6
            BittersMixer -> 0.4
            Accent -> 0.3
            Garnish -> 0.1
        }
}

/**
 * Strictness and weighting knobs for the matching engine, plus user accept/reject overrides.
 * See Data Model.md's "Matching Score & Strictness" — this must stay in lockstep with iOS's
 * `MatchPreferences`.
 */
data class MatchPreferences(
    val strictness: Double = 0.5,
    val roleWeights: Map<IngredientRole, Double> = IngredientRole.entries.associateWith { it.defaultWeight },
    /** requiredStyleId -> a substitute styleId the user has told us to accept at quality 1.0. */
    val acceptOverrides: Map<UUID, UUID> = emptyMap(),
    /** requiredStyleId -> substitute styleIds the user has told us are never acceptable. */
    val rejectOverrides: Map<UUID, Set<UUID>> = emptyMap(),
) {
    fun weight(role: IngredientRole): Double = roleWeights[role] ?: role.defaultWeight

    /** `threshold = 0.45 + strictness * 0.40`, per the Data Model spec. */
    val similarityThreshold: Double
        get() = 0.45 + strictness * 0.40

    fun isRejected(substituteId: UUID, requiredId: UUID): Boolean =
        rejectOverrides[requiredId]?.contains(substituteId) ?: false

    companion object {
        val Default = MatchPreferences()
    }
}

enum class MatchType { Exact, Partial }

/**
 * One resolved substitution within a [RecipeMatchResult] — only present when a different style
 * than the one the recipe calls for was used.
 */
data class SubstitutionDetail(
    val required: IngredientStyle,
    val substitute: IngredientStyle,
    val similarityScore: Double,
    val note: String,
    val ratioHint: String?,
)

data class RecipeMatchResult(
    val recipe: Recipe,
    /** The recipe's ingredient lines — Room splits these into their own table, unlike iOS's
     *  `Recipe.ingredients`, so the result carries them for the detail screen. */
    val ingredients: List<RecipeIngredient>,
    val matchScore: Double,
    val matchType: MatchType,
    val substitutions: List<SubstitutionDetail>,
)
