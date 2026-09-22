package dev.martinloeseth.norsemixology.ui.favourites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.martinloeseth.norsemixology.data.local.FavouriteRecipe
import dev.martinloeseth.norsemixology.data.local.Recipe
import dev.martinloeseth.norsemixology.data.repository.FavouritesRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.UUID

data class FavouritesUiState(
    val favourites: List<FavouriteRecipe> = emptyList(),
    val favouritedIds: Set<UUID> = emptySet(),
    val isLoading: Boolean = true,
) {
    val isEmpty: Boolean get() = !isLoading && favourites.isEmpty()
}

/**
 * App-wide favourites state — one instance shared by the detail screen's heart, result cards, and
 * the Favourites tab, so they never disagree (mirrors iOS's `FavouritesViewModel`).
 */
class FavouritesViewModel(private val repository: FavouritesRepository) : ViewModel() {
    val uiState: StateFlow<FavouritesUiState> = repository.all()
        .map { favourites -> FavouritesUiState(favourites, favourites.map { it.recipeId }.toSet(), isLoading = false) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), FavouritesUiState())

    fun isFavourited(recipeId: UUID): Boolean = recipeId in uiState.value.favouritedIds

    fun toggle(recipe: Recipe) {
        viewModelScope.launch { repository.toggle(recipe) }
    }

    fun remove(favourite: FavouriteRecipe) {
        viewModelScope.launch { repository.remove(favourite.recipeId) }
    }
}
