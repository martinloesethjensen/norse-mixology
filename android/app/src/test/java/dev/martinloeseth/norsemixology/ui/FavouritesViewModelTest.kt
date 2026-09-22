package dev.martinloeseth.norsemixology.ui

import androidx.lifecycle.viewModelScope
import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.FavouritesRepository
import dev.martinloeseth.norsemixology.inMemoryDatabase
import dev.martinloeseth.norsemixology.ui.favourites.FavouritesViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FavouritesViewModelTest {
    private lateinit var database: NorseMixologyDatabase
    private lateinit var repository: FavouritesRepository
    private lateinit var viewModel: FavouritesViewModel
    private val catalog = SeedFiles.recipeCatalog()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        database = inMemoryDatabase()
        repository = FavouritesRepository(database.favouriteDao())
        viewModel = FavouritesViewModel(repository)
    }

    @After
    fun tearDown() {
        viewModel.viewModelScope.cancel()
        database.close()
        Dispatchers.resetMain()
    }

    private fun recipe(name: String) = catalog.recipes.first { it.recipe.name == name }.recipe

    @Test
    fun togglingTwiceLeavesItNotFavourited() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        val negroni = recipe("Negroni")

        viewModel.toggle(negroni)
        viewModel.uiState.first { it.favouritedIds.contains(negroni.id) }
        assertTrue(viewModel.isFavourited(negroni.id))

        viewModel.toggle(negroni)
        viewModel.uiState.first { !it.favouritedIds.contains(negroni.id) }
        assertFalse(viewModel.isFavourited(negroni.id))
    }

    @Test
    fun anEmptyFavouritesListIsReportedOnceLoaded() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }

        val state = viewModel.uiState.first { !it.isLoading }

        assertTrue(state.isEmpty)
    }

    @Test
    fun removeTakesItOutOfTheState() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        val negroni = recipe("Negroni")
        viewModel.toggle(negroni)
        val favourite = viewModel.uiState.first { it.favourites.isNotEmpty() }.favourites.single()

        viewModel.remove(favourite)

        assertTrue(viewModel.uiState.first { it.favourites.isEmpty() }.isEmpty)
    }
}
