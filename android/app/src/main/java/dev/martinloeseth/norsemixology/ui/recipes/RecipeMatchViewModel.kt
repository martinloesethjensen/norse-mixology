package dev.martinloeseth.norsemixology.ui.recipes

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.domain.RecipeCatalog
import dev.martinloeseth.norsemixology.domain.Taxonomy
import dev.martinloeseth.norsemixology.domain.matching.MatchPreferences
import dev.martinloeseth.norsemixology.domain.matching.MatchingEngine
import dev.martinloeseth.norsemixology.domain.matching.RecipeMatchResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface FindRecipesState {
    data object Idle : FindRecipesState
    data object Loading : FindRecipesState

    /**
     * [requestId] is otherwise-unused but must be unique per call to [RecipeMatchViewModel.findRecipes]:
     * two searches over an unchanged cabinet produce structurally-equal `results`, and a `StateFlow`
     * consumer keyed on equality (e.g. `LaunchedEffect(state)`) would then never see a second Ready
     * as a new value, so a repeat "Find Recipes" tap would silently fail to navigate.
     */
    data class Ready(val results: List<RecipeMatchResult>, val requestId: Long) : FindRecipesState
}

/**
 * Runs the on-device matching engine (see `domain/matching/`) against the current cabinet and the
 * seeded recipe catalog. Shared across the Cabinet flow's nav entries (Cabinet -> results) the
 * same way `AddIngredientViewModel` is shared for the add flow.
 */
class RecipeMatchViewModel(
    private val cabinetRepository: CabinetRepository,
    private val taxonomy: StateFlow<Taxonomy>,
    private val recipeCatalog: StateFlow<RecipeCatalog>,
) : ViewModel() {
    private val _state = MutableStateFlow<FindRecipesState>(FindRecipesState.Idle)
    val state: StateFlow<FindRecipesState> = _state
    private var nextRequestId = 0L

    fun findRecipes() {
        val requestId = ++nextRequestId
        viewModelScope.launch {
            _state.value = FindRecipesState.Loading
            val cabinet = cabinetRepository.allItems().first()
            val results = withContext(Dispatchers.Default) {
                MatchingEngine.match(cabinet, recipeCatalog.value.recipes, taxonomy.value, MatchPreferences.Default)
            }
            _state.value = FindRecipesState.Ready(results, requestId)
        }
    }

    fun consumeResults() {
        _state.value = FindRecipesState.Idle
    }
}
