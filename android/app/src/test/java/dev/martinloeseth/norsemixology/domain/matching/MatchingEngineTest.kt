package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.domain.CabinetItems
import dev.martinloeseth.norsemixology.domain.RecipeCatalog
import dev.martinloeseth.norsemixology.domain.Taxonomy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirrors iOS's `MatchingServiceTests` exactly — same cabinets, same recipe names, same expected
 * outcomes — since this engine's output must be identical to the Swift implementation. See the
 * Phase 8 doc's "Cross-Platform Consistency Check": a Negroni cabinet (Gin, Campari, Sweet
 * Vermouth) must score 1.0 / exact on both platforms, and Bourbon -> Rye must produce an
 * equivalent partial match with a substitution note on both.
 */
class MatchingEngineTest {
    private val taxonomy: Taxonomy = SeedFiles.taxonomy()
    private val catalog: RecipeCatalog = SeedFiles.recipeCatalog()

    private fun style(name: String) = taxonomy.stylesById.values.first { it.name == name }
    private fun cabinetItem(styleName: String) = CabinetItems.create(style(styleName), taxonomy, brand = null)

    @Test
    fun exactNegroniCabinetScoresOne() {
        val cabinet = listOf(
            cabinetItem("London Dry Gin"),
            cabinetItem("Bitter Aperitif"),
            cabinetItem("Sweet/Rosso Vermouth"),
        )

        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy)
        val negroni = results.first { it.recipe.name == "Negroni" }

        assertEquals(MatchType.Exact, negroni.matchType)
        assertEquals(1.0, negroni.matchScore, 0.0001)
        assertEquals("Negroni", results.first().recipe.name)
    }

    @Test
    fun bourbonReplacedByRyeMakesOldFashionedPartial() {
        val cabinet = listOf(
            cabinetItem("Rye Whiskey"), // recipe calls for Bourbon
            cabinetItem("Demerara Syrup"),
            cabinetItem("Angostura Bitters"),
        )

        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy, MatchPreferences.Default)
        val oldFashioned = results.first { it.recipe.name == "Old Fashioned" }

        assertEquals(MatchType.Partial, oldFashioned.matchType)
        assertTrue(oldFashioned.matchScore < 1.0)
        val sub = oldFashioned.substitutions.first { it.required.name == "Bourbon" }
        assertEquals("Rye Whiskey", sub.substitute.name)
        assertTrue(sub.note.isNotEmpty())
    }

    @Test
    fun emptyCabinetReturnsEmptyResults() {
        val results = MatchingEngine.match(emptyList(), catalog.recipes, taxonomy)
        assertTrue(results.isEmpty())
    }

    @Test
    fun cabinetWithNoUsefulIngredientsReturnsNoResults() {
        // Only a garnish-role fresh herb — no recipe's base spirit can resolve from this alone.
        val cabinet = listOf(cabinetItem("Fresh Basil"))
        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy)
        assertTrue(results.isEmpty())
    }

    @Test
    fun ginReplacedByVodkaDropsNegroniEntirely() {
        val cabinet = listOf(
            cabinetItem("Neutral Vodka"), // different family than Gin — no cosine fallback possible
            cabinetItem("Bitter Aperitif"),
            cabinetItem("Sweet/Rosso Vermouth"),
        )

        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy)
        assertFalse(results.any { it.recipe.name == "Negroni" })
    }

    @Test
    fun stricterPreferencesSurfaceFewerPartialMatches() {
        // A broad, imperfect cabinet likely to generate several borderline substitutions.
        val cabinet = listOf(
            "Rye Whiskey", "Contemporary Gin", "White/Blanco Rum", "Blanco Tequila",
            "Demerara Syrup", "Angostura Bitters", "Lime Juice", "Lemon Juice", "Simple Syrup",
        ).map { cabinetItem(it) }

        val adventurous = MatchPreferences.Default.copy(strictness = 0.0)
        val strict = MatchPreferences.Default.copy(strictness = 1.0)

        val adventurousResults = MatchingEngine.match(cabinet, catalog.recipes, taxonomy, adventurous)
        val strictResults = MatchingEngine.match(cabinet, catalog.recipes, taxonomy, strict)

        val adventurousPartials = adventurousResults.count { it.matchType == MatchType.Partial }
        val strictPartials = strictResults.count { it.matchType == MatchType.Partial }

        assertTrue(strictPartials <= adventurousPartials)
        assertTrue("Expected strictness to meaningfully reduce partial matches for this cabinet", strictPartials < adventurousPartials)
    }

    @Test
    fun resultsAreSortedExactFirstThenByScore() {
        val cabinet = listOf(
            cabinetItem("London Dry Gin"),
            cabinetItem("Bitter Aperitif"),
            cabinetItem("Sweet/Rosso Vermouth"),
            cabinetItem("Rye Whiskey"),
            cabinetItem("Demerara Syrup"),
            cabinetItem("Angostura Bitters"),
        )

        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy)

        var seenPartial = false
        var previousScore = 1.0
        for (result in results) {
            if (result.matchType == MatchType.Partial) {
                seenPartial = true
                assertTrue(result.matchScore <= previousScore)
                previousScore = result.matchScore
            } else {
                assertFalse("All exact results must sort before any partial result", seenPartial)
            }
        }
    }
}
