package dev.martinloeseth.norsemixology.ui.cabinet

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Kitchen
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.data.local.CabinetItem
import dev.martinloeseth.norsemixology.ui.components.FlavorProfileIndicator
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

/** Widest the Cabinet list grows on tablets, so rows stay readable. */
private val MaxContentWidth = 720.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CabinetScreen(
    viewModel: CabinetViewModel,
    onAddIngredient: () -> Unit,
    onFindRecipes: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val colors = NorseTheme.colors

    Scaffold(
        modifier = modifier,
        containerColor = colors.background,
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(stringResource(R.string.cabinet_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize)) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary),
            )
        },
        // The bar is the Scaffold's bottomBar (not part of the list) so the FAB floats above it.
        bottomBar = { if (!state.isLoading && !state.isEmpty) FindRecipesBar(onClick = onFindRecipes) },
        floatingActionButton = {
            FloatingActionButton(onClick = onAddIngredient, containerColor = colors.accent, contentColor = colors.onAccent) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_ingredient))
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            when {
                state.isLoading -> Unit
                state.isEmpty -> EmptyCabinet(onAddIngredient)
                else -> CabinetList(state, onToggleCategory = viewModel::toggleCategory, onRemove = viewModel::remove)
            }
        }
    }
}

@Composable
private fun EmptyCabinet(onAddIngredient: () -> Unit) {
    val colors = NorseTheme.colors
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Filled.Kitchen, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(64.dp))
        Spacer(Modifier.size(16.dp))
        Text(stringResource(R.string.cabinet_empty_title), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize), color = colors.textPrimary, textAlign = TextAlign.Center)
        Spacer(Modifier.size(8.dp))
        Text(stringResource(R.string.cabinet_empty_body), style = NorseTheme.type.body, color = colors.textSecondary, textAlign = TextAlign.Center)
        Spacer(Modifier.size(24.dp))
        Button(
            onClick = onAddIngredient,
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.onAccent),
            modifier = Modifier.heightIn(min = 48.dp),
        ) { Text(stringResource(R.string.add_ingredient)) }
    }
}

@Composable
private fun CabinetList(state: CabinetUiState, onToggleCategory: (String) -> Unit, onRemove: (CabinetItem) -> Unit) {
    LazyColumn(Modifier.widthIn(max = MaxContentWidth).fillMaxSize(), contentPadding = PaddingValues(bottom = 88.dp)) {
        state.groups.forEach { group ->
            val collapsed = group.category in state.collapsedCategories
            item(key = "header-${group.category}") {
                CategoryHeader(group.category, group.items.size, collapsed) { onToggleCategory(group.category) }
            }
            if (!collapsed) {
                items(group.items, key = { it.id }) { item ->
                    SwipeableCabinetRow(item, onRemove = { onRemove(item) })
                }
            }
        }
    }
}

@Composable
private fun FindRecipesBar(onClick: () -> Unit) {
    val colors = NorseTheme.colors
    Column(
        // navigationBarsPadding: on tablets there is no bottom nav bar to absorb the system inset.
        Modifier.fillMaxWidth().background(colors.background).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Button(
            onClick = onClick,
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.onAccent),
            modifier = Modifier.widthIn(max = MaxContentWidth).fillMaxWidth().heightIn(min = 48.dp),
        ) {
            Text(stringResource(R.string.find_recipes))
        }
    }
}

@Composable
private fun CategoryHeader(category: String, count: Int, collapsed: Boolean, onToggle: () -> Unit) {
    val colors = NorseTheme.colors
    val actionLabel = stringResource(if (collapsed) R.string.expand_category else R.string.collapse_category, category)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(onClickLabel = actionLabel, onClick = onToggle)
            .padding(horizontal = 16.dp)
            .semantics(mergeDescendants = true) { heading() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            category.uppercase(),
            style = NorseTheme.type.label,
            color = colors.textSecondary,
            modifier = Modifier.weight(1f),
        )
        Text(pluralStringResource(R.plurals.items_count, count, count), style = NorseTheme.type.body, color = colors.textSecondary)
        Icon(if (collapsed) Icons.Filled.ExpandMore else Icons.Filled.ExpandLess, contentDescription = null, tint = colors.textSecondary)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeableCabinetRow(item: CabinetItem, onRemove: () -> Unit) {
    val colors = NorseTheme.colors
    val removeLabel = stringResource(R.string.remove_from_cabinet)
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) { onRemove(); true } else false
        },
    )

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(horizontal = 24.dp),
                contentAlignment = Alignment.CenterEnd,
            ) { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer) }
        },
        // TalkBack users can't swipe, so the same action is exposed as a custom accessibility action.
        modifier = Modifier.semantics { customActions = listOf(CustomAccessibilityAction(removeLabel) { onRemove(); true }) },
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(colors.surface)
                .heightIn(min = 64.dp)
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(item.displayName, style = NorseTheme.type.heading, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(
                    if (item.style == item.displayName) item.family else "${item.style} · ${item.family}",
                    style = NorseTheme.type.body,
                    color = colors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            FlavorProfileIndicator(item.flavorProfile)
        }
    }
}
