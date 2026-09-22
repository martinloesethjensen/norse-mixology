package dev.martinloeseth.norsemixology.ui

import androidx.lifecycle.viewModelScope
import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.domain.CabinetItems
import dev.martinloeseth.norsemixology.inMemoryDatabase
import dev.martinloeseth.norsemixology.ui.recipes.RecipeViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RecipeViewModelTest {
    private lateinit var database: NorseMixologyDatabase
    private lateinit var cabinetRepository: CabinetRepository
    private lateinit var viewModel: RecipeViewModel
    private val taxonomy = SeedFiles.taxonomy()
    private val catalog = SeedFiles.recipeCatalog()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        database = inMemoryDatabase()
        cabinetRepository = CabinetRepository(database.cabinetDao())
        viewModel = RecipeViewModel(cabinetRepository, MutableStateFlow(taxonomy), MutableStateFlow(catalog))
    }

    @After
    fun tearDown() {
        viewModel.viewModelScope.cancel()
        database.close()
        Dispatchers.resetMain()
    }

    private fun style(name: String) = taxonomy.stylesById.values.first { it.name == name }
    private suspend fun addStyles(vararg names: String) = names.forEach { name ->
        cabinetRepository.add(CabinetItems.create(style(name), taxonomy, null))
    }

    @Test
    fun refreshGroupsAnExactNegroniCabinetAsPerfect() = runTest {
        addStyles("London Dry Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth")

        viewModel.refresh()

        val state = viewModel.uiState.first { !it.isLoading }
        assertTrue(state.grouped.perfect.any { it.recipe.name == "Negroni" })
    }

    @Test
    fun refreshWithAnEmptyCabinetProducesNoResults() = runTest {
        viewModel.refresh()

        val state = viewModel.uiState.first { !it.isLoading }
        assertTrue(state.grouped.isEmpty)
    }

    @Test
    fun selectingARecipeExposesItAsSelectedRecipe() = runTest {
        addStyles("London Dry Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth")
        viewModel.refresh()
        val negroni = viewModel.uiState.first { !it.isLoading }.grouped.perfect.first { it.recipe.name == "Negroni" }

        viewModel.select(negroni.recipe.id)

        assertTrue(viewModel.uiState.value.selectedRecipe?.recipe?.name == "Negroni")
    }

    @Test
    fun aSelectedRecipeIsClearedIfItDropsOutOfTheResultsOnRefresh() = runTest {
        addStyles("London Dry Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth")
        viewModel.refresh()
        val negroni = viewModel.uiState.first { !it.isLoading }.grouped.perfect.first { it.recipe.name == "Negroni" }
        viewModel.select(negroni.recipe.id)

        // Empty the cabinet entirely, then refresh — Negroni can no longer be made.
        cabinetRepository.allItems().first().forEach { cabinetRepository.remove(it) }
        viewModel.refresh()

        assertNull(viewModel.uiState.first { it.grouped.isEmpty }.selectedRecipeId)
    }
}
