package dev.martinloeseth.norsemixology.ui.recipes

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.domain.RecipeCatalog
import dev.martinloeseth.norsemixology.domain.Taxonomy
import dev.martinloeseth.norsemixology.domain.matching.GroupedMatchResults
import dev.martinloeseth.norsemixology.domain.matching.MatchPreferences
import dev.martinloeseth.norsemixology.domain.matching.MatchingEngine
import dev.martinloeseth.norsemixology.domain.matching.RecipeMatchResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

data class RecipeBrowserUiState(
    val grouped: GroupedMatchResults = GroupedMatchResults.Empty,
    /** Styles in the cabinet at the time of the last refresh — the detail screen uses these to
     *  tell "exact" from "unavailable" ingredients. */
    val cabinetStyleIds: Set<UUID> = emptySet(),
    val isLoading: Boolean = true,
    /** Drives the detail pane on Expanded-width (tablet) layouts. */
    val selectedRecipeId: UUID? = null,
) {
    private val all: List<RecipeMatchResult> get() = grouped.perfect + grouped.almost + grouped.exploring
    val selectedRecipe: RecipeMatchResult? get() = selectedRecipeId?.let { id -> all.firstOrNull { it.recipe.id == id } }
    fun result(id: UUID): RecipeMatchResult? = all.firstOrNull { it.recipe.id == id }
}

/**
 * Holds the latest on-device match for the Recipes tab. Shared app-wide (like iOS's
 * `RecipeBrowserViewModel`) so Cabinet's "Find Recipes" and the Recipes tab read the same results.
 *
 * Matching ~150 bundled recipes is near-instant (see Phase 3 notes), so there is no loading state
 * beyond the very first composition.
 */
class RecipeViewModel(
    private val cabinetRepository: CabinetRepository,
    private val taxonomy: StateFlow<Taxonomy>,
    private val recipeCatalog: StateFlow<RecipeCatalog>,
) : ViewModel() {
    private val _uiState = MutableStateFlow(RecipeBrowserUiState())
    val uiState: StateFlow<RecipeBrowserUiState> = _uiState

    /** Re-runs the match against the cabinet currently in Room. */
    fun refresh() {
        viewModelScope.launch {
            val cabinet = cabinetRepository.allItems().first()
            val results = MatchingEngine.match(cabinet, recipeCatalog.value.recipes, taxonomy.value, MatchPreferences.Default)
            val cabinetStyleIds = cabinet.map { it.ingredientStyleId }.toSet()
            _uiState.update { state ->
                // A recipe can drop out of the results when the cabinet changes.
                val selected = state.selectedRecipeId?.takeIf { id -> results.any { it.recipe.id == id } }
                RecipeBrowserUiState(GroupedMatchResults.from(results), cabinetStyleIds, isLoading = false, selectedRecipeId = selected)
            }
        }
    }

    fun select(recipeId: UUID?) {
        _uiState.update { it.copy(selectedRecipeId = recipeId) }
    }
}
