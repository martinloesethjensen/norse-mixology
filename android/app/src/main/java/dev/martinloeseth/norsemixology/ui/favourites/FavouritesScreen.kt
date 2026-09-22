package dev.martinloeseth.norsemixology.ui.favourites

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.data.local.FavouriteRecipe
import dev.martinloeseth.norsemixology.domain.RecipeWithIngredients
import dev.martinloeseth.norsemixology.domain.displayName
import dev.martinloeseth.norsemixology.ui.recipes.OutlinePill
import dev.martinloeseth.norsemixology.ui.recipes.icon
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme
import java.text.DateFormat
import java.util.UUID

/** The Favourites tab: saved recipes, most recently favourited first. */
@Composable
fun FavouritesScreen(
    state: FavouritesUiState,
    recipesById: Map<UUID, RecipeWithIngredients>,
    onSelect: (UUID) -> Unit,
    onRemove: (FavouriteRecipe) -> Unit,
    modifier: Modifier = Modifier,
    selectedRecipeId: UUID? = null,
) {
    val colors = NorseTheme.colors
    if (state.isEmpty) {
        Column(
            modifier.fillMaxSize().padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(stringResource(R.string.favourites_empty_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize), color = colors.textPrimary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.favourites_empty_body), style = NorseTheme.type.body, color = colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        }
        return
    }

    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        items(state.favourites, key = { it.id }) { favourite ->
            FavouriteRow(favourite, recipesById[favourite.recipeId], favourite.recipeId == selectedRecipeId, onSelect, onRemove)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FavouriteRow(
    favourite: FavouriteRecipe,
    entry: RecipeWithIngredients?,
    isSelected: Boolean,
    onSelect: (UUID) -> Unit,
    onRemove: (FavouriteRecipe) -> Unit,
) {
    val removeLabel = stringResource(R.string.unfavourite)
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value -> if (value == SwipeToDismissBoxValue.EndToStart) { onRemove(favourite); true } else false },
    )

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer, RoundedCornerShape(14.dp)).padding(horizontal = 24.dp),
                contentAlignment = Alignment.CenterEnd,
            ) { Icon(Icons.Filled.Delete, contentDescription = removeLabel, tint = MaterialTheme.colorScheme.onErrorContainer) }
        },
    ) {
        FavouriteCard(favourite, entry, isSelected, onSelect)
    }
}

@Composable
private fun FavouriteCard(favourite: FavouriteRecipe, entry: RecipeWithIngredients?, isSelected: Boolean, onSelect: (UUID) -> Unit) {
    val colors = NorseTheme.colors
    val recipe = entry?.recipe
    val dateText = DateFormat.getDateInstance(DateFormat.MEDIUM).format(favourite.dateFavourited)

    Column(
        Modifier
            .fillMaxWidth()
            .alpha(if (recipe != null) 1f else 0.6f)
            .background(colors.surfaceRaised, RoundedCornerShape(14.dp))
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) colors.accent else colors.border, RoundedCornerShape(14.dp))
            .let { base -> if (recipe != null) base.clickable { onSelect(favourite.recipeId) } else base }
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(favourite.recipeName, style = NorseTheme.type.heading, color = colors.textPrimary, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (recipe != null) {
                Icon(recipe.glassType.icon, contentDescription = stringResource(R.string.glass_content_description, recipe.glassType.displayName), tint = colors.textSecondary)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (recipe != null) {
                OutlinePill(recipe.difficulty.displayName)
            } else {
                Text(stringResource(R.string.recipe_no_longer_available), style = NorseTheme.type.body, color = colors.textSecondary)
            }
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.favourited_on, dateText), style = NorseTheme.type.body, color = colors.textSecondary)
        }
    }
}
