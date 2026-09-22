package dev.martinloeseth.norsemixology.ui.recipes

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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
import dev.martinloeseth.norsemixology.ui.favourites.FavouritesViewModel
import dev.martinloeseth.norsemixology.ui.isExpandedWidth
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable private data object RecipeListKey : NavKey
@Serializable private data class RecipeDetailKey(val id: String) : NavKey

/**
 * The Recipes tab: matches for the current cabinet, grouped into Perfect Match / Almost There /
 * Worth Exploring. Compact width pushes the detail screen; Expanded width (tablet) shows results
 * and detail side by side, mirroring iOS's `NavigationSplitView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecipesFlow(container: AppContainer, viewModel: RecipeViewModel, favouritesViewModel: FavouritesViewModel) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val taxonomy by container.taxonomy.collectAsStateWithLifecycle()
    val recipeCatalog by container.recipeCatalog.collectAsStateWithLifecycle()
    val favouritesState by favouritesViewModel.uiState.collectAsStateWithLifecycle()

    // The bundled catalog loads asynchronously at launch; re-match once it's ready or changes.
    LaunchedEffect(recipeCatalog) { viewModel.refresh() }

    val colors = NorseTheme.colors

    if (isExpandedWidth()) {
        Row(Modifier.fillMaxSize()) {
            Column(Modifier.weight(0.42f)) {
                CenterAlignedTopAppBar(
                    title = { Text(stringResource(R.string.recipes_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize)) },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary),
                )
                RecipeBrowserScreen(
                    state = state,
                    favouritesViewModel = favouritesViewModel,
                    onRefresh = viewModel::refresh,
                    onSelectRecipe = viewModel::select,
                    selectedRecipeId = state.selectedRecipeId,
                )
            }
            VerticalDivider(color = colors.border)
            Box(Modifier.weight(0.58f)) {
                val selected = state.selectedRecipe
                if (selected != null) {
                    RecipeDetailScreen(
                        recipe = selected.recipe,
                        ingredients = selected.ingredients,
                        match = selected,
                        cabinetStyleIds = state.cabinetStyleIds,
                        taxonomy = taxonomy,
                        isFavourite = selected.recipe.id in favouritesState.favouritedIds,
                        onToggleFavourite = { favouritesViewModel.toggle(selected.recipe) },
                        onBack = null,
                    )
                } else {
                    EmptyDetailPane()
                }
            }
        }
    } else {
        val backStack = rememberNavBackStack(RecipeListKey)
        NavDisplay(
            backStack = backStack,
            onBack = { backStack.removeLastOrNull() },
            entryProvider = entryProvider {
                entry<RecipeListKey> {
                    Scaffold(
                        containerColor = colors.background,
                        topBar = {
                            CenterAlignedTopAppBar(
                                title = { Text(stringResource(R.string.recipes_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize)) },
                                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary),
                            )
                        },
                    ) { padding ->
                        RecipeBrowserScreen(
                            state = state,
                            favouritesViewModel = favouritesViewModel,
                            onRefresh = viewModel::refresh,
                            onSelectRecipe = { id -> backStack.add(RecipeDetailKey(id.toString())) },
                            modifier = Modifier.padding(padding),
                        )
                    }
                }
                entry<RecipeDetailKey> { key ->
                    val result = state.result(UUID.fromString(key.id))
                    if (result != null) {
                        RecipeDetailScreen(
                            recipe = result.recipe,
                            ingredients = result.ingredients,
                            match = result,
                            cabinetStyleIds = state.cabinetStyleIds,
                            taxonomy = taxonomy,
                            isFavourite = result.recipe.id in favouritesState.favouritedIds,
                            onToggleFavourite = { favouritesViewModel.toggle(result.recipe) },
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
