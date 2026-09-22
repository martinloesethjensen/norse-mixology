package dev.martinloeseth.norsemixology.data

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.FavouritesRepository
import dev.martinloeseth.norsemixology.inMemoryDatabase
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.Date

class FavouritesRepositoryTest {
    private lateinit var database: NorseMixologyDatabase
    private lateinit var repository: FavouritesRepository
    private val catalog = SeedFiles.recipeCatalog()

    @Before
    fun setUp() {
        database = inMemoryDatabase()
        repository = FavouritesRepository(database.favouriteDao())
    }

    @After
    fun tearDown() = database.close()

    private fun recipe(name: String) = catalog.recipes.first { it.recipe.name == name }.recipe

    @Test
    fun saveInsertsAndAllEmitsIt() = runTest {
        repository.save(recipe("Negroni"))

        assertEquals(listOf("Negroni"), repository.all().first().map { it.recipeName })
    }

    @Test
    fun savingTheSameRecipeTwiceIsANoOp() = runTest {
        repository.save(recipe("Negroni"))
        repository.save(recipe("Negroni"))

        assertEquals(1, repository.all().first().size)
    }

    @Test
    fun removeDeletesTheRecord() = runTest {
        repository.save(recipe("Negroni"))

        repository.remove(recipe("Negroni").id)

        assertTrue(repository.all().first().isEmpty())
    }

    @Test
    fun isFavouritedReflectsState() = runTest {
        assertFalse(repository.isFavourited(recipe("Negroni").id))

        repository.save(recipe("Negroni"))

        assertTrue(repository.isFavourited(recipe("Negroni").id))
    }

    @Test
    fun toggleSavesThenRemoves() = runTest {
        val isNowFavourited = repository.toggle(recipe("Negroni"))
        assertTrue(isNowFavourited)
        assertTrue(repository.isFavourited(recipe("Negroni").id))

        val isNowUnfavourited = repository.toggle(recipe("Negroni"))
        assertFalse(isNowUnfavourited)
        assertFalse(repository.isFavourited(recipe("Negroni").id))
    }

    @Test
    fun allIsSortedMostRecentlyFavouritedFirst() = runTest {
        repository.save(recipe("Negroni"), date = Date(1_000))
        repository.save(recipe("Martini"), date = Date(2_000))

        assertEquals(listOf("Martini", "Negroni"), repository.all().first().map { it.recipeName })
    }
}
