package dev.martinloeseth.norsemixology.ui.cabinet

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.martinloeseth.norsemixology.data.local.CabinetItem
import dev.martinloeseth.norsemixology.data.repository.CabinetRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class CabinetGroup(val category: String, val items: List<CabinetItem>)

data class CabinetUiState(
    val groups: List<CabinetGroup> = emptyList(),
    val collapsedCategories: Set<String> = emptySet(),
    val isLoading: Boolean = true,
) {
    val items: List<CabinetItem> get() = groups.flatMap { it.items }
    val isEmpty: Boolean get() = !isLoading && groups.isEmpty()
}

class CabinetViewModel(private val repository: CabinetRepository) : ViewModel() {
    private val collapsedCategories = MutableStateFlow<Set<String>>(emptySet())

    val uiState: StateFlow<CabinetUiState> =
        combine(repository.allItems(), collapsedCategories) { items, collapsed ->
            CabinetUiState(groups = group(items), collapsedCategories = collapsed, isLoading = false)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CabinetUiState())

    fun remove(item: CabinetItem) {
        viewModelScope.launch { repository.remove(item) }
    }

    fun toggleCategory(category: String) {
        collapsedCategories.update { if (category in it) it - category else it + category }
    }

    companion object {
        /** Categories A→Z, items A→Z within each — the same grouping as the iOS Cabinet. */
        fun group(items: List<CabinetItem>): List<CabinetGroup> =
            items.groupBy { it.category }
                .map { (category, group) -> CabinetGroup(category, group.sortedBy { it.displayName.lowercase() }) }
                .sortedBy { it.category.lowercase() }
    }
}
