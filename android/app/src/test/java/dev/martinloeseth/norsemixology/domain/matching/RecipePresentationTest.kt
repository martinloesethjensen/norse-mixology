package dev.martinloeseth.norsemixology.domain.matching

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.domain.CabinetItems
import dev.martinloeseth.norsemixology.domain.RecipeCatalog
import dev.martinloeseth.norsemixology.domain.Taxonomy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RecipePresentationTest {
    private val taxonomy: Taxonomy = SeedFiles.taxonomy()
    private val catalog: RecipeCatalog = SeedFiles.recipeCatalog()

    private fun style(name: String) = taxonomy.stylesById.values.first { it.name == name }
    private fun cabinetItem(styleName: String) = CabinetItems.create(style(styleName), taxonomy, brand = null)

    @Test
    fun exactMatchesGoToPerfect() {
        val cabinet = listOf(cabinetItem("London Dry Gin"), cabinetItem("Bitter Aperitif"), cabinetItem("Sweet/Rosso Vermouth"))
        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy)
        val negroni = results.first { it.recipe.name == "Negroni" }

        val grouped = GroupedMatchResults.from(results)

        assertTrue(grouped.perfect.any { it.recipe.name == "Negroni" })
        assertTrue(grouped.almost.none { it.recipe.name == "Negroni" })
        assertTrue(grouped.exploring.none { it.recipe.name == "Negroni" })
        assertEquals(negroni, grouped.perfect.first { it.recipe.name == "Negroni" })
    }

    @Test
    fun partialWithOneSubstitutionGoesToAlmost() {
        val cabinet = listOf(cabinetItem("Rye Whiskey"), cabinetItem("Demerara Syrup"), cabinetItem("Angostura Bitters"))
        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy)
        val oldFashioned = results.first { it.recipe.name == "Old Fashioned" }
        check(oldFashioned.substitutions.size == 1) { "test assumes exactly one substitution for this cabinet" }

        val grouped = GroupedMatchResults.from(results)

        assertTrue(grouped.almost.any { it.recipe.name == "Old Fashioned" })
        assertTrue(grouped.perfect.none { it.recipe.name == "Old Fashioned" })
        assertTrue(grouped.exploring.none { it.recipe.name == "Old Fashioned" })
    }

    @Test
    fun partialWithTwoOrMoreSubstitutionsGoesToExploring() {
        val result = RecipeMatchResult(
            recipe = catalog.recipes.first().recipe,
            ingredients = catalog.recipes.first().ingredients,
            matchScore = 0.7,
            matchType = MatchType.Partial,
            substitutions = listOf(sub(), sub()),
        )

        val grouped = GroupedMatchResults.from(listOf(result))

        assertEquals(1, grouped.exploring.size)
        assertTrue(grouped.almost.isEmpty())
        assertTrue(grouped.perfect.isEmpty())
    }

    @Test
    fun groupOrderIsNeverReSorted() {
        val cabinet = listOf(
            cabinetItem("London Dry Gin"), cabinetItem("Bitter Aperitif"), cabinetItem("Sweet/Rosso Vermouth"),
            cabinetItem("Rye Whiskey"), cabinetItem("Demerara Syrup"), cabinetItem("Angostura Bitters"),
        )
        val results = MatchingEngine.match(cabinet, catalog.recipes, taxonomy)

        val grouped = GroupedMatchResults.from(results)

        assertEquals(results.filter { it.matchType == MatchType.Exact }, grouped.perfect)
    }

    @Test
    fun matchBadgeExactForFullMatch() {
        val cabinet = listOf(cabinetItem("London Dry Gin"), cabinetItem("Bitter Aperitif"), cabinetItem("Sweet/Rosso Vermouth"))
        val negroni = MatchingEngine.match(cabinet, catalog.recipes, taxonomy).first { it.recipe.name == "Negroni" }

        assertEquals(MatchBadgeState.Exact, MatchBadgeState.of(negroni))
    }

    @Test
    fun matchBadgeCountsSubstitutionsForPartialMatch() {
        val cabinet = listOf(cabinetItem("Rye Whiskey"), cabinetItem("Demerara Syrup"), cabinetItem("Angostura Bitters"))
        val oldFashioned = MatchingEngine.match(cabinet, catalog.recipes, taxonomy).first { it.recipe.name == "Old Fashioned" }

        assertEquals(MatchBadgeState.Substituted(oldFashioned.substitutions.size), MatchBadgeState.of(oldFashioned))
    }

    @Test
    fun ingredientAvailabilityRowsReflectSubstitutionExactAndUnavailable() {
        val cabinet = listOf(cabinetItem("Rye Whiskey"), cabinetItem("Demerara Syrup"), cabinetItem("Angostura Bitters"))
        val oldFashioned = MatchingEngine.match(cabinet, catalog.recipes, taxonomy).first { it.recipe.name == "Old Fashioned" }
        val cabinetStyleIds = cabinet.map { it.ingredientStyleId }.toSet()

        val rows = RecipeAvailability.rows(oldFashioned, cabinetStyleIds)

        val bourbonRow = rows.first { it.substitution?.required?.name == "Bourbon" }
        assertEquals(AvailabilityStatus.Substituted, bourbonRow.status)
        val bittersRow = rows.first { it.ingredient.ingredientStyleId == style("Angostura Bitters").id }
        assertEquals(AvailabilityStatus.Exact, bittersRow.status)
    }

    @Test
    fun negroniGarnishRowIsUnavailableEvenThoughTheRecipeIsAPerfectMatch() {
        val cabinet = listOf(cabinetItem("London Dry Gin"), cabinetItem("Bitter Aperitif"), cabinetItem("Sweet/Rosso Vermouth"))
        val negroni = MatchingEngine.match(cabinet, catalog.recipes, taxonomy).first { it.recipe.name == "Negroni" }
        val cabinetStyleIds = cabinet.map { it.ingredientStyleId }.toSet()

        val rows = RecipeAvailability.rows(negroni, cabinetStyleIds)

        assertTrue("expected at least one unavailable (garnish) row on an otherwise-perfect Negroni", rows.any { it.status == AvailabilityStatus.Unavailable })
    }

    private fun sub(): SubstitutionDetail {
        val a = style("Bourbon")
        val b = style("Rye Whiskey")
        return SubstitutionDetail(required = a, substitute = b, similarityScore = 0.8, note = "test", ratioHint = null)
    }
}
