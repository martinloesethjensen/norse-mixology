package dev.martinloeseth.norsemixology.data

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.CabinetItem
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.domain.CabinetItems
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

class CabinetRepositoryTest {
    private lateinit var database: NorseMixologyDatabase
    private lateinit var repository: CabinetRepository
    private val taxonomy = SeedFiles.taxonomy()

    @Before
    fun setUp() {
        database = inMemoryDatabase()
        repository = CabinetRepository(database.cabinetDao())
    }

    @After
    fun tearDown() = database.close()

    private fun item(styleName: String, brand: String? = null): CabinetItem =
        CabinetItems.create(taxonomy.stylesById.values.first { it.name == styleName }, taxonomy, brand)

    @Test
    fun addInsertsAndAllItemsEmitsIt() = runTest {
        repository.add(item("London Dry Gin"))

        assertEquals(listOf("London Dry Gin"), repository.allItems().first().map { it.displayName })
    }

    @Test
    fun removeDeletesTheItem() = runTest {
        val gin = item("London Dry Gin")
        repository.add(gin)

        repository.remove(gin)

        assertTrue(repository.allItems().first().isEmpty())
    }

    @Test
    fun containsReflectsTheStyle() = runTest {
        val gin = item("London Dry Gin")
        assertFalse(repository.contains(gin.ingredientStyleId))

        repository.add(gin)

        assertTrue(repository.contains(gin.ingredientStyleId))
    }

    @Test
    fun theSameStyleCannotBeAddedTwice() = runTest {
        assertTrue(repository.add(item("London Dry Gin")))
        assertFalse("second add is rejected", repository.add(item("London Dry Gin", brand = "Tanqueray")))

        assertEquals(1, repository.allItems().first().size)
    }

    @Test
    fun allItemsAreSortedByCategoryThenName() = runTest {
        repository.add(item("Sweet/Rosso Vermouth"))
        repository.add(item("London Dry Gin"))
        repository.add(item("Bourbon"))
        repository.add(item("Angostura Bitters"))

        val items = repository.allItems().first()

        assertEquals(items.sortedWith(compareBy({ it.category.lowercase() }, { it.displayName.lowercase() })), items)
        assertEquals("Garnish", items.first().category)
    }

    @Test
    fun aSavedItemKeepsItsFlavourProfileAndDate() = runTest {
        val date = Date(1_700_000_000_000)
        val gin = CabinetItems.create(taxonomy.stylesById.values.first { it.name == "London Dry Gin" }, taxonomy, null, dateAdded = date)
        repository.add(gin)

        val stored = repository.allItems().first().single()

        assertEquals(gin.flavorProfile, stored.flavorProfile)
        assertEquals(date, stored.dateAdded)
        assertEquals(gin.id, stored.id)
    }
}
