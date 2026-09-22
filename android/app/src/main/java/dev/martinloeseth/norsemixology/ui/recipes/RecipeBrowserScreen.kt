package dev.martinloeseth.norsemixology.ui.recipes

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.domain.matching.RecipeMatchResult
import dev.martinloeseth.norsemixology.ui.favourites.FavouritesViewModel
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme
import java.util.UUID

/** The grouped result cards (Perfect Match / Almost There / Worth Exploring). */
@Composable
fun RecipeBrowserScreen(
    state: RecipeBrowserUiState,
    favouritesViewModel: FavouritesViewModel,
    onRefresh: () -> Unit,
    onSelectRecipe: (UUID) -> Unit,
    modifier: Modifier = Modifier,
    selectedRecipeId: UUID? = null,
) {
    val colors = NorseTheme.colors
    var isRefreshing by remember { mutableStateOf(false) }
    LaunchedEffect(state) { isRefreshing = false }

    if (state.grouped.isEmpty) {
        if (!state.isLoading) {
            Column(
                modifier.fillMaxSize().padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(stringResource(R.string.recipes_empty_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize), color = colors.textPrimary, textAlign = TextAlign.Center)
                Text(stringResource(R.string.recipes_empty_body), style = NorseTheme.type.body, color = colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
            }
        }
        return
    }

    val favouritesState by favouritesViewModel.uiState.collectAsStateWithLifecycle()
    val perfectTitle = stringResource(R.string.perfect_match_title)
    val perfectSubtitle = stringResource(R.string.perfect_match_subtitle)
    val almostTitle = stringResource(R.string.almost_there_title)
    val almostSubtitle = stringResource(R.string.almost_there_subtitle)
    val exploringTitle = stringResource(R.string.worth_exploring_title)
    val exploringSubtitle = stringResource(R.string.worth_exploring_subtitle)

    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = { isRefreshing = true; onRefresh() },
        modifier = modifier.fillMaxSize(),
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            resultSection(perfectTitle, perfectSubtitle, state.grouped.perfect, favouritesState.favouritedIds, selectedRecipeId, onSelectRecipe)
            resultSection(almostTitle, almostSubtitle, state.grouped.almost, favouritesState.favouritedIds, selectedRecipeId, onSelectRecipe)
            resultSection(exploringTitle, exploringSubtitle, state.grouped.exploring, favouritesState.favouritedIds, selectedRecipeId, onSelectRecipe)
        }
    }
}

private fun LazyListScope.resultSection(
    title: String,
    subtitle: String,
    matches: List<RecipeMatchResult>,
    favouritedIds: Set<UUID>,
    selectedRecipeId: UUID?,
    onSelectRecipe: (UUID) -> Unit,
) {
    if (matches.isEmpty()) return
    item(key = "header-$title") {
        SectionHeader(title, subtitle, matches.size)
    }
    items(matches, key = { it.recipe.id }) { result ->
        RecipeCard(
            result = result,
            isFavourited = result.recipe.id in favouritedIds,
            isSelected = result.recipe.id == selectedRecipeId,
            modifier = Modifier.fillMaxWidth().clickable { onSelectRecipe(result.recipe.id) },
        )
    }
}

@Composable
private fun SectionHeader(title: String, subtitle: String, count: Int) {
    val colors = NorseTheme.colors
    Column {
        Text(
            stringResource(R.string.section_header_with_count, title, count),
            style = NorseTheme.type.heading,
            color = colors.textPrimary,
        )
        Text(subtitle, style = NorseTheme.type.body, color = colors.textSecondary)
    }
}
