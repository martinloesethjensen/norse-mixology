package dev.martinloeseth.norsemixology.data

import dev.martinloeseth.norsemixology.InMemorySeedFlagStore
import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.data.repository.TaxonomyRepository
import dev.martinloeseth.norsemixology.data.seed.CatalogSeeder
import dev.martinloeseth.norsemixology.data.seed.SeedResult
import dev.martinloeseth.norsemixology.domain.CabinetItems
import dev.martinloeseth.norsemixology.inMemoryDatabase
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class CatalogSeederTest {
    private lateinit var database: NorseMixologyDatabase
    private val flags = InMemorySeedFlagStore()

    @Before
    fun setUp() { database = inMemoryDatabase() }

    @After
    fun tearDown() = database.close()

    private fun seeder(recipes: () -> String = SeedFiles::recipesText) =
        CatalogSeeder(database, flags, SeedFiles::taxonomyText, recipes)

    @Test
    fun seedsTheFullCatalogIntoRoom() = runTest {
        val result = seeder().seedIfNeeded()

        assertTrue(result is SeedResult.Seeded)
        assertTrue(database.taxonomyDao().styleCount() >= 60)
        assertTrue(database.recipeDao().recipeCount() >= 150)
        assertTrue(database.recipeDao().ingredientCount() > database.recipeDao().recipeCount())
    }

    @Test
    fun theSecondLaunchDoesNothing() = runTest {
        seeder().seedIfNeeded()
        val styles = database.taxonomyDao().styleCount()

        assertEquals(SeedResult.AlreadySeeded, seeder().seedIfNeeded())
        assertEquals(styles, database.taxonomyDao().styleCount())
    }

    @Test
    fun reseedingReplacesTheCatalogWithoutDuplicatesAndKeepsTheCabinet() = runTest {
        seeder().seedIfNeeded()
        val taxonomy = TaxonomyRepository(database.taxonomyDao()).load()
        val cabinet = CabinetRepository(database.cabinetDao())
        cabinet.add(CabinetItems.create(taxonomy.stylesById.values.first { it.name == "London Dry Gin" }, taxonomy, null))
        val styles = database.taxonomyDao().styleCount()
        val recipes = database.recipeDao().recipeCount()

        flags.version = 0 // pretend the bundled catalog version was bumped
        seeder().seedIfNeeded()

        assertEquals(styles, database.taxonomyDao().styleCount())
        assertEquals(recipes, database.recipeDao().recipeCount())
        assertEquals("the user's cabinet survives a catalog reseed", 1, cabinet.allItems().first().size)
    }

    @Test
    fun aMalformedRecipeIsSkippedAndReported() = runTest {
        val corrupted = SeedFiles.recipesText()
            .replaceFirst(Regex("\"method\"\\s*:\\s*\"[^\"]+\""), "\"method\": \"levitate\"")

        val result = seeder { corrupted }.seedIfNeeded() as SeedResult.Seeded

        assertEquals(1, result.skippedRecipes)
    }

    @Test
    fun theLoadedTaxonomyMatchesTheHierarchyInTheSeedFile() = runTest {
        seeder().seedIfNeeded()

        val loaded = TaxonomyRepository(database.taxonomyDao()).load()
        val fromFile = SeedFiles.taxonomy()

        assertEquals(fromFile.categories.map { it.category.name }, loaded.categories.map { it.category.name })
        assertEquals(fromFile.stylesById.keys, loaded.stylesById.keys)
    }
}
