package dev.martinloeseth.norsemixology.ui

import dev.martinloeseth.norsemixology.SeedFiles
import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.domain.CabinetItems
import dev.martinloeseth.norsemixology.inMemoryDatabase
import dev.martinloeseth.norsemixology.ui.cabinet.AddIngredientMode
import dev.martinloeseth.norsemixology.ui.cabinet.AddIngredientViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AddIngredientViewModelTest {
    private lateinit var database: NorseMixologyDatabase
    private lateinit var cabinet: CabinetRepository
    private lateinit var viewModel: AddIngredientViewModel
    private val taxonomy = SeedFiles.taxonomy()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        database = inMemoryDatabase()
        cabinet = CabinetRepository(database.cabinetDao())
        viewModel = AddIngredientViewModel(MutableStateFlow(taxonomy), cabinet)
    }

    @After
    fun tearDown() {
        // Stop the view model's sharing coroutine first: it would otherwise still be reading Room
        // (WhileSubscribed keeps it alive for 5 s) when the database closes.
        viewModel.viewModelScope.cancel()
        database.close()
        Dispatchers.resetMain()
    }

    private fun style(name: String) = taxonomy.stylesById.values.first { it.name == name }

    @Test
    fun typingGinSurfacesTheGinStyles() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }

        viewModel.onQueryChange("gin")

        val names = viewModel.uiState.first { it.results.isNotEmpty() }.results.map { it.name }
        assertTrue("London Dry Gin" in names)
        assertTrue("Contemporary Gin" in names)
    }

    @Test
    fun aBlankQueryShowsNoResults() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }

        viewModel.onQueryChange("   ")

        assertTrue(viewModel.uiState.first { it.query == "   " }.results.isEmpty())
    }

    @Test
    fun tappingANewStyleOpensTheConfirmationSheet() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }

        viewModel.onStyleTapped(style("London Dry Gin"))

        assertEquals("London Dry Gin", viewModel.uiState.first { it.pendingStyle != null }.pendingStyle?.name)
    }

    @Test
    fun tappingAnOwnedStyleReportsADuplicateAndOpensNothing() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        cabinet.add(CabinetItems.create(style("London Dry Gin"), taxonomy, null))
        viewModel.uiState.first { style("London Dry Gin").id in it.ownedStyleIds }
        var duplicates = 0
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.alreadyInCabinet.collect { duplicates++ } }

        viewModel.onStyleTapped(style("London Dry Gin"))

        assertEquals(1, duplicates)
        assertNull(viewModel.uiState.value.pendingStyle)
    }

    @Test
    fun confirmingAddsTheStyleWithItsBrandAndClosesTheSheet() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        viewModel.onStyleTapped(style("Contemporary Gin"))
        viewModel.uiState.first { it.pendingStyle != null }
        var added = false

        viewModel.confirm("  Hendrick's ") { added = true }

        val stored = cabinet.allItems().first { it.isNotEmpty() }.single()
        assertEquals("Hendrick's Contemporary Gin", stored.displayName)
        assertEquals("Hendrick's", stored.brand)
        assertEquals("Gin", stored.family)
        assertEquals("Spirit", stored.category)
        assertTrue(added)
        assertNull(viewModel.uiState.first { it.pendingStyle == null }.pendingStyle)
    }

    @Test
    fun aBlankBrandIsStoredAsNoBrand() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        viewModel.onStyleTapped(style("Angostura Bitters"))
        viewModel.uiState.first { it.pendingStyle != null }

        viewModel.confirm("   ") {}

        val stored = cabinet.allItems().first { it.isNotEmpty() }.single()
        assertNull(stored.brand)
        assertEquals("Angostura Bitters", stored.displayName)
        assertEquals("Garnish", stored.category)
    }

    @Test
    fun resetStartsTheFlowOverInSearchWithNoSheet() = runTest {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        viewModel.onModeChange(AddIngredientMode.Browse)
        viewModel.onQueryChange("rum")
        viewModel.onStyleTapped(style("London Dry Gin"))

        viewModel.reset()

        val state = viewModel.uiState.first { it.query.isEmpty() }
        assertEquals(AddIngredientMode.Search, state.mode)
        assertNull(state.pendingStyle)
    }
}
