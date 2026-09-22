package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.data.local.FlavorProfile
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.domain.Taxonomy
import java.util.UUID
import kotlin.math.sqrt

/** Cosine similarity over the 9 flavour dimensions — excludes `abv`, per the Data Model spec. */
object FlavorSimilarity {
    fun cosine(a: FlavorProfile, b: FlavorProfile): Double {
        val pairs = listOf(
            a.sweetness to b.sweetness, a.bitterness to b.bitterness, a.smokiness to b.smokiness,
            a.citrus to b.citrus, a.floral to b.floral, a.spice to b.spice,
            a.herbal to b.herbal, a.fruity to b.fruity, a.oaky to b.oaky,
        )
        val dot = pairs.sumOf { (x, y) -> x * y }
        val magA = sqrt(pairs.sumOf { (x, _) -> x * x })
        val magB = sqrt(pairs.sumOf { (_, y) -> y * y })
        if (magA <= 0 || magB <= 0) return 0.0
        return dot / (magA * magB)
    }
}

/**
 * Tier 3 curated substitutes — different family, same functional role, which the same-family
 * cosine fallback would never surface on its own. Looked up by style name (stable across
 * regenerations of the taxonomy's deterministic ids) and resolved against the loaded taxonomy at
 * match time. Content must match the iOS `CuratedSubstitutions.all` table exactly.
 */
data class CuratedSubstitutionRule(val requiredStyleName: String, val substituteStyleName: String, val baseQuality: Double)

object CuratedSubstitutions {
    val all: List<CuratedSubstitutionRule> = listOf(
        CuratedSubstitutionRule("Dry Vermouth", "Fino Sherry", 0.6),
        CuratedSubstitutionRule("Sweet/Rosso Vermouth", "Ruby Port", 0.55),
        CuratedSubstitutionRule("Orgeat", "Amaretto", 0.55),
        CuratedSubstitutionRule("Coffee Liqueur", "Hazelnut Liqueur", 0.5),
        CuratedSubstitutionRule("Mezcal", "Scotch Single Malt (Islay)", 0.5),
    )

    /** Bidirectional table keyed by required style id, candidates in rule order. */
    fun table(taxonomy: Taxonomy): Map<UUID, List<Pair<UUID, Double>>> {
        val stylesByName = taxonomy.stylesById.values.associateBy { it.name }
        val result = mutableMapOf<UUID, MutableList<Pair<UUID, Double>>>()
        for (rule in all) {
            val required = stylesByName[rule.requiredStyleName] ?: continue
            val substitute = stylesByName[rule.substituteStyleName] ?: continue
            result.getOrPut(required.id) { mutableListOf() }.add(substitute.id to rule.baseQuality)
            result.getOrPut(substitute.id) { mutableListOf() }.add(required.id to rule.baseQuality)
        }
        return result
    }
}

/** Generates human-readable substitution notes and presentation-only ratio hints. */
object SubstitutionNote {
    private class Dimension(val moreAdjective: String, val lessAdjective: String, val value: (FlavorProfile) -> Double)

    private val dimensions = listOf(
        Dimension("sweeter", "drier") { it.sweetness },
        Dimension("more bitter", "less bitter") { it.bitterness },
        Dimension("smokier", "less smoky") { it.smokiness },
        Dimension("more citrusy", "less citrusy") { it.citrus },
        Dimension("more floral", "less floral") { it.floral },
        Dimension("spicier", "milder") { it.spice },
        Dimension("more herbal", "less herbal") { it.herbal },
        Dimension("fruitier", "less fruity") { it.fruity },
        Dimension("oakier", "less oaky") { it.oaky },
    )

    /** A minimum delta before a dimension is worth mentioning. */
    private const val SIGNIFICANCE_THRESHOLD = 0.05

    fun generate(required: IngredientStyle, substitute: IngredientStyle): String {
        val deltas = dimensions
            .map { dim -> dim to (dim.value(substitute.flavorProfile) - dim.value(required.flavorProfile)) }
            .filter { (_, delta) -> kotlin.math.abs(delta) >= SIGNIFICANCE_THRESHOLD }
            .sortedByDescending { (_, delta) -> kotlin.math.abs(delta) }

        if (deltas.isEmpty()) {
            return "${substitute.name} is a close match for ${required.name} — the cocktail should taste very similar."
        }

        val top = deltas.take(2)
        val adjectives = top.map { (dim, delta) -> if (delta >= 0) dim.moreAdjective else dim.lessAdjective }
        val adjectivePhrase = if (adjectives.size == 1) adjectives[0] else "${adjectives[0]} and ${adjectives[1]}"

        // Prefer the second-ranked dimension for the summary clause when there is one — it tends
        // to read as the more natural "the drink will be ___" descriptor rather than repeating
        // the lead dimension verbatim.
        val (effectDim, effectDelta) = if (top.size > 1) top[1] else top[0]
        val effect = if (effectDelta >= 0) effectDim.moreAdjective else effectDim.lessAdjective

        return "${substitute.name} is $adjectivePhrase than ${required.name} — the cocktail will be $effect."
    }

    /** Presentation-only — never affects `matchScore`. */
    fun ratioHint(role: IngredientRole, required: IngredientStyle, substitute: IngredientStyle): String? {
        if (role != IngredientRole.SweetenerSour) return null
        val delta = substitute.flavorProfile.sweetness - required.flavorProfile.sweetness
        return when {
            delta >= 0.2 -> "It's noticeably sweeter — try using about 25% less."
            delta <= -0.2 -> "It's noticeably less sweet — you may want to use a bit more."
            else -> null
        }
    }
}
