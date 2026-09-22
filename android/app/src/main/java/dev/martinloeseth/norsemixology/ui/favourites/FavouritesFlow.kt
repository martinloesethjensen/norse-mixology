package dev.martinloeseth.norsemixology.ui.favourites

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import dev.martinloeseth.norsemixology.AppContainer
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.domain.RecipeWithIngredients
import dev.martinloeseth.norsemixology.domain.matching.MatchPreferences
import dev.martinloeseth.norsemixology.domain.matching.MatchingEngine
import dev.martinloeseth.norsemixology.ui.isExpandedWidth
import dev.martinloeseth.norsemixology.ui.recipes.RecipeDetailScreen
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable private data object FavouritesListKey : NavKey
@Serializable private data class FavouriteDetailKey(val id: String) : NavKey

/**
 * The Favourites tab: saved recipes, most recently favourited first. Rows open the full recipe
 * from the bundled catalog and its availability is worked out against the cabinet as it is right
 * now — always available, no loading state.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavouritesFlow(container: AppContainer, favouritesViewModel: FavouritesViewModel) {
    val state by favouritesViewModel.uiState.collectAsStateWithLifecycle()
    val taxonomy by container.taxonomy.collectAsStateWithLifecycle()
    val recipeCatalog by container.recipeCatalog.collectAsStateWithLifecycle()
    val cabinet by container.cabinetRepository.allItems().collectAsStateWithLifecycle(initialValue = emptyList())
    val colors = NorseTheme.colors

    val recipesById = recipeCatalog.recipes.associateBy { it.recipe.id }
    val cabinetStyleIds = cabinet.map { it.ingredientStyleId }.toSet()

    fun matchFor(entry: RecipeWithIngredients) =
        MatchingEngine.match(cabinet, listOf(entry), taxonomy, MatchPreferences.Default).firstOrNull()

    if (isExpandedWidth()) {
        var selectedId by rememberSaveable { mutableStateOf<UUID?>(null) }
        Row(Modifier.fillMaxSize()) {
            Column(Modifier.weight(0.42f)) {
                CenterAlignedTopAppBar(
                    title = { Text(stringResource(R.string.favourites_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize)) },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary),
                )
                FavouritesScreen(state, recipesById, onSelect = { selectedId = it }, onRemove = favouritesViewModel::remove, selectedRecipeId = selectedId)
            }
            VerticalDivider(color = colors.border)
            Box(Modifier.weight(0.58f)) {
                val entry = selectedId?.let { recipesById[it] }
                if (entry != null) {
                    RecipeDetailScreen(
                        recipe = entry.recipe,
                        ingredients = entry.ingredients,
                        match = matchFor(entry),
                        cabinetStyleIds = cabinetStyleIds,
                        taxonomy = taxonomy,
                        isFavourite = entry.recipe.id in state.favouritedIds,
                        onToggleFavourite = { favouritesViewModel.toggle(entry.recipe) },
                        onBack = null,
                    )
                } else {
                    EmptyDetailPane()
                }
            }
        }
    } else {
        val backStack = rememberNavBackStack(FavouritesListKey)
        NavDisplay(
            backStack = backStack,
            onBack = { backStack.removeLastOrNull() },
            entryProvider = entryProvider {
                entry<FavouritesListKey> {
                    Scaffold(
                        containerColor = colors.background,
                        topBar = {
                            CenterAlignedTopAppBar(
                                title = { Text(stringResource(R.string.favourites_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize)) },
                                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary),
                            )
                        },
                    ) { padding ->
                        FavouritesScreen(
                            state = state,
                            recipesById = recipesById,
                            onSelect = { id -> backStack.add(FavouriteDetailKey(id.toString())) },
                            onRemove = favouritesViewModel::remove,
                            modifier = Modifier.padding(padding),
                        )
                    }
                }
                entry<FavouriteDetailKey> { key ->
                    val entry = recipesById[UUID.fromString(key.id)]
                    if (entry != null) {
                        RecipeDetailScreen(
                            recipe = entry.recipe,
                            ingredients = entry.ingredients,
                            match = matchFor(entry),
                            cabinetStyleIds = cabinetStyleIds,
                            taxonomy = taxonomy,
                            isFavourite = entry.recipe.id in state.favouritedIds,
                            onToggleFavourite = { favouritesViewModel.toggle(entry.recipe) },
                            onBack = { backStack.removeLastOrNull() },
                        )
                    }
                }
            },
        )
    }
}

@Composable
private fun EmptyDetailPane() {
    val colors = NorseTheme.colors
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(stringResource(R.string.select_a_recipe_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize), color = colors.textPrimary, textAlign = TextAlign.Center)
        Text(stringResource(R.string.select_a_recipe_body), style = NorseTheme.type.body, color = colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
    }
}
