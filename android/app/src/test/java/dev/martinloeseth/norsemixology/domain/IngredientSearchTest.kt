package dev.martinloeseth.norsemixology.domain

import dev.martinloeseth.norsemixology.SeedFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors the iOS `IngredientSearchTests`. */
class IngredientSearchTest {
    private val taxonomy = SeedFiles.taxonomy()

    @Test
    fun searchGinSurfacesMultipleGinStyles() {
        val results = IngredientSearch.search("gin", taxonomy)
        val names = results.map { it.name }.toSet()
        assertTrue("London Dry Gin" in names)
        assertTrue("Contemporary Gin" in names)
        assertTrue(results.size >= 5)
    }

    @Test
    fun searchMatchesBrandName() {
        assertTrue(IngredientSearch.search("Tanqueray", taxonomy).any { it.name == "London Dry Gin" })
    }

    @Test
    fun searchIsCaseInsensitive() {
        assertEquals(IngredientSearch.search("GIN", taxonomy).size, IngredientSearch.search("gin", taxonomy).size)
    }

    @Test
    fun blankQueryReturnsNothing() {
        assertTrue(IngredientSearch.search("   ", taxonomy).isEmpty())
        assertTrue(IngredientSearch.search("", taxonomy).isEmpty())
    }

    @Test
    fun matchesOnFamilyName() {
        // "Whiskey" is a family; its styles don't all contain the word themselves.
        val results = IngredientSearch.search("whiskey", taxonomy)
        assertTrue(results.any { it.name == "Bourbon" })
    }

    @Test
    fun resultsFollowTheCatalogOrderWithoutDuplicates() {
        val results = IngredientSearch.search("gin", taxonomy)
        assertEquals(results.distinctBy { it.id }.size, results.size)
    }
}
