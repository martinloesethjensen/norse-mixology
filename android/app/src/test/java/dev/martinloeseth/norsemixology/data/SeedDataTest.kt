package dev.martinloeseth.norsemixology.data

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.seed.CatalogParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SeedDataTest {
    @Test
    fun taxonomyHasAtLeast60Styles() {
        val rows = SeedFiles.taxonomyRows()
        assertTrue("styles = ${rows.styles.size}", rows.styles.size >= 60)
        assertTrue(rows.categories.isNotEmpty() && rows.families.isNotEmpty())
    }

    @Test
    fun recipesHaveAtLeast150Recipes() {
        val parsed = CatalogParser.parseRecipes(SeedFiles.recipesText())
        assertTrue("recipes = ${parsed.rows.recipes.size}", parsed.rows.recipes.size >= 150)
        assertEquals("the bundled catalog is clean", 0, parsed.skippedCount)
        assertTrue(parsed.rows.ingredients.size > parsed.rows.recipes.size)
    }

    @Test
    fun everyRecipeIngredientPointsAtARealStyle() {
        val styleIds = SeedFiles.taxonomyRows().styles.map { it.id }.toSet()
        val dangling = CatalogParser.parseRecipes(SeedFiles.recipesText()).rows.ingredients
            .filterNot { it.ingredientStyleId in styleIds }
        assertTrue("dangling ingredient references: ${dangling.size}", dangling.isEmpty())
    }

    @Test
    fun taxonomyKeepsTheAuthoredOrderAndHierarchy() {
        val taxonomy = SeedFiles.taxonomy()
        val gin = taxonomy.stylesById.values.first { it.name == "London Dry Gin" }
        assertEquals("Gin", taxonomy.familyNamesById[gin.familyId])
        assertEquals("Spirit", taxonomy.categoryNamesById[gin.categoryId])
    }

    @Test
    fun parsesTheSameCountsAsTheIosBundle() {
        val iosTaxonomy = CatalogParser.parseTaxonomy(java.io.File(SeedFiles.iosResourcesDir, "taxonomy.json").readText())
        val iosRecipes = CatalogParser.parseRecipes(java.io.File(SeedFiles.iosResourcesDir, "recipes.json").readText())
        val taxonomy = SeedFiles.taxonomyRows()
        val recipes = CatalogParser.parseRecipes(SeedFiles.recipesText())

        assertEquals(iosTaxonomy.styles.size, taxonomy.styles.size)
        assertEquals(iosRecipes.rows.recipes.size, recipes.rows.recipes.size)
    }

    @Test
    fun iosBundleIsByteIdenticalToTheSharedSeedData() {
        // Guards against the two platforms silently drifting apart.
        for (name in listOf("taxonomy.json", "recipes.json")) {
            assertEquals(
                "ios/NorseMixology/Resources/$name differs from seed-data/$name",
                java.io.File(SeedFiles.dir, name).readText(),
                java.io.File(SeedFiles.iosResourcesDir, name).readText(),
            )
        }
    }

    @Test
    fun aMalformedRecipeIsSkippedNotFatal() {
        val original = CatalogParser.parseRecipes(SeedFiles.recipesText())
        val corrupted = SeedFiles.recipesText()
            .replaceFirst(Regex("\"glassType\"\\s*:\\s*\"[^\"]+\""), "\"glassType\": \"not-a-real-glass\"")

        val parsed = CatalogParser.parseRecipes(corrupted)

        assertEquals(1, parsed.skippedCount)
        assertEquals(original.rows.recipes.size - 1, parsed.rows.recipes.size)
        assertFalse(parsed.rows.recipes.any { it.id == original.rows.recipes.first().id })
    }

    @Test
    fun aRecipeFileThatIsNotAnArrayStillFails() {
        assertThrows(Exception::class.java) { CatalogParser.parseRecipes("""{"oops": true}""") }
    }
}
