package dev.martinloeseth.norsemixology.ui.cabinet

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import dev.martinloeseth.norsemixology.domain.CabinetItems
import dev.martinloeseth.norsemixology.domain.IngredientSearch
import dev.martinloeseth.norsemixology.domain.Taxonomy
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

enum class AddIngredientMode { Search, Browse }

data class AddIngredientUiState(
    val mode: AddIngredientMode = AddIngredientMode.Search,
    val query: String = "",
    val taxonomy: Taxonomy = Taxonomy.Empty,
    /** Search results — empty while the query is blank. */
    val results: List<IngredientStyle> = emptyList(),
    /** Ingredient styles already in the cabinet (shown checked and greyed out). */
    val ownedStyleIds: Set<UUID> = emptySet(),
    /** The style awaiting confirmation in the bottom sheet, if any. */
    val pendingStyle: IngredientStyle? = null,
) {
    val hasQuery: Boolean get() = query.isNotBlank()
}

/**
 * Drives Search, Browse and the confirmation sheet. One instance is shared by every screen of the
 * add-ingredient flow so a style picked from Browse and one picked from Search behave identically.
 */
class AddIngredientViewModel(
    private val taxonomy: StateFlow<Taxonomy>,
    private val cabinet: CabinetRepository,
) : ViewModel() {
    private val mode = MutableStateFlow(AddIngredientMode.Search)
    private val query = MutableStateFlow("")
    private val pendingStyle = MutableStateFlow<IngredientStyle?>(null)

    private val _alreadyInCabinet = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    /** Emits each time the user taps an ingredient that is already in the cabinet. */
    val alreadyInCabinet: SharedFlow<Unit> = _alreadyInCabinet

    val uiState: StateFlow<AddIngredientUiState> = combine(
        taxonomy,
        cabinet.allItems().map { items -> items.map { it.ingredientStyleId }.toSet() },
        mode,
        query,
        pendingStyle,
    ) { taxonomy, owned, mode, query, pending ->
        AddIngredientUiState(
            mode = mode,
            query = query,
            taxonomy = taxonomy,
            results = IngredientSearch.search(query, taxonomy),
            ownedStyleIds = owned,
            pendingStyle = pending,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AddIngredientUiState())

    fun onModeChange(newMode: AddIngredientMode) { mode.value = newMode }

    fun onQueryChange(newQuery: String) { query.value = newQuery }

    /** Starts the add flow from scratch (fresh Search, empty query, no open sheet). */
    fun reset() {
        mode.value = AddIngredientMode.Search
        query.value = ""
        pendingStyle.value = null
    }

    /** Opens the confirmation sheet, or reports a duplicate if the style is already owned. */
    fun onStyleTapped(style: IngredientStyle) {
        if (style.id in uiState.value.ownedStyleIds) {
            _alreadyInCabinet.tryEmit(Unit)
        } else {
            pendingStyle.value = style
        }
    }

    fun dismissConfirmation() { pendingStyle.value = null }

    /** Saves the pending style (with an optional brand) and calls [onAdded] once it is stored. */
    fun confirm(brand: String, onAdded: () -> Unit) {
        val style = pendingStyle.value ?: return
        viewModelScope.launch {
            cabinet.add(CabinetItems.create(style, taxonomy.value, brand))
            pendingStyle.update { null }
            onAdded()
        }
    }
}
