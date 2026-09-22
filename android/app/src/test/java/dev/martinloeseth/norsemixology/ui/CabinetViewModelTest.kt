package dev.martinloeseth.norsemixology.ui

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.domain.CabinetItems
import dev.martinloeseth.norsemixology.inMemoryDatabase
import dev.martinloeseth.norsemixology.ui.cabinet.CabinetViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CabinetViewModelTest {
    private lateinit var database: NorseMixologyDatabase
    private lateinit var repository: CabinetRepository
    private lateinit var viewModel: CabinetViewModel
    private val taxonomy = SeedFiles.taxonomy()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        database = inMemoryDatabase()
        repository = CabinetRepository(database.cabinetDao())
        viewModel = CabinetViewModel(repository)
    }

    @After
    fun tearDown() {
        // Stop the view model's sharing coroutine first: it would otherwise still be reading Room
        // (WhileSubscribed keeps it alive for 5 s) when the database closes.
        viewModel.viewModelScope.cancel()
        database.close()
        Dispatchers.resetMain()
    }

    private suspend fun addStyles(vararg names: String) = names.forEach { name ->
        repository.add(CabinetItems.create(taxonomy.stylesById.values.first { it.name == name }, taxonomy, null))
    }

    @Test
    fun groupsItemsByCategoryAlphabetically() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        addStyles("Sweet/Rosso Vermouth", "London Dry Gin", "Bourbon", "Angostura Bitters")

        val state = viewModel.uiState.first { it.items.size == 4 }

        assertEquals(listOf("Garnish", "Spirit", "Wine & Fortified"), state.groups.map { it.category })
        assertEquals(listOf("Bourbon", "London Dry Gin"), state.groups.first { it.category == "Spirit" }.items.map { it.displayName })
    }

    @Test
    fun anEmptyCabinetIsReportedOnceLoaded() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }

        val state = viewModel.uiState.first { !it.isLoading }

        assertTrue(state.isEmpty)
        assertTrue(state.groups.isEmpty())
    }

    @Test
    fun removeTakesTheItemOutOfTheState() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        addStyles("London Dry Gin", "Bourbon")
        val gin = viewModel.uiState.first { it.items.size == 2 }.items.first { it.displayName == "London Dry Gin" }

        viewModel.remove(gin)

        assertEquals(listOf("Bourbon"), viewModel.uiState.first { it.items.size == 1 }.items.map { it.displayName })
    }

    @Test
    fun aCategoryCanBeCollapsedAndExpanded() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        addStyles("London Dry Gin")
        viewModel.uiState.first { it.items.size == 1 }

        viewModel.toggleCategory("Spirit")
        assertTrue("Spirit" in viewModel.uiState.first { "Spirit" in it.collapsedCategories }.collapsedCategories)

        viewModel.toggleCategory("Spirit")
        assertFalse("Spirit" in viewModel.uiState.first { "Spirit" !in it.collapsedCategories }.collapsedCategories)
    }

    @Test
    fun groupingIsCaseInsensitive() {
        val items = listOf("bourbon", "Angostura", "Absinthe").map { name ->
            CabinetItems.create(taxonomy.stylesById.values.first(), taxonomy, null).copy(
                id = java.util.UUID.randomUUID(), displayName = name, category = "Spirit",
            )
        }

        assertEquals(listOf("Absinthe", "Angostura", "bourbon"), CabinetViewModel.group(items).single().items.map { it.displayName })
    }
}
