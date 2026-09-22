package dev.martinloeseth.norsemixology.ui.cabinet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.domain.CategoryNode
import dev.martinloeseth.norsemixology.domain.FamilyNode
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme
import java.util.UUID

private val MaxContentWidth = 720.dp

/**
 * Shows the "Already in your cabinet" message as a snackbar each time the user taps an owned
 * ingredient. (TalkBack announces snackbars, so this is also the accessible path.)
 */
@Composable
private fun rememberDuplicateSnackbarState(viewModel: AddIngredientViewModel): SnackbarHostState {
    val snackbarHostState = remember { SnackbarHostState() }
    val message = stringResource(R.string.already_in_cabinet)
    LaunchedEffect(viewModel) {
        viewModel.alreadyInCabinet.collect {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(message, duration = SnackbarDuration.Short)
        }
    }
    return snackbarHostState
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FlowScaffold(
    title: String,
    onBack: () -> Unit,
    snackbarHostState: SnackbarHostState,
    content: @Composable (Modifier) -> Unit,
) {
    val colors = NorseTheme.colors
    Scaffold(
        containerColor = colors.background,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.navigate_back)) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary, navigationIconContentColor = colors.textPrimary),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            content(Modifier.widthIn(max = MaxContentWidth).fillMaxSize())
        }
    }
}

@Composable
fun AddIngredientScreen(
    viewModel: AddIngredientViewModel,
    onBack: () -> Unit,
    onOpenCategory: (UUID) -> Unit,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = rememberDuplicateSnackbarState(viewModel)

    FlowScaffold(stringResource(R.string.add_ingredient), onBack, snackbarHostState) { modifier ->
        Column(modifier) {
            ModeSelector(state.mode, viewModel::onModeChange)
            when (state.mode) {
                AddIngredientMode.Search -> SearchContent(state, viewModel::onQueryChange, viewModel::onStyleTapped)
                AddIngredientMode.Browse -> CategoryList(state.taxonomy.categories) { onOpenCategory(it.category.id) }
            }
        }
    }
}

@Composable
private fun ModeSelector(mode: AddIngredientMode, onModeChange: (AddIngredientMode) -> Unit) {
    val colors = NorseTheme.colors
    val options = listOf(AddIngredientMode.Search to R.string.mode_search, AddIngredientMode.Browse to R.string.mode_browse)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        options.forEachIndexed { index, (option, label) ->
            SegmentedButton(
                selected = mode == option,
                onClick = { onModeChange(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = colors.accent, activeContentColor = colors.onAccent, activeBorderColor = colors.accent,
                    inactiveContainerColor = colors.surface, inactiveContentColor = colors.textPrimary, inactiveBorderColor = colors.border,
                ),
            ) { Text(stringResource(label)) }
        }
    }
}

@Composable
private fun SearchContent(state: AddIngredientUiState, onQueryChange: (String) -> Unit, onStyleTapped: (IngredientStyle) -> Unit) {
    val colors = NorseTheme.colors
    OutlinedTextField(
        value = state.query,
        onValueChange = onQueryChange,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        singleLine = true,
        placeholder = { Text(stringResource(R.string.search_placeholder)) },
        trailingIcon = {
            if (state.query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.clear_search)) }
            }
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface,
            focusedBorderColor = colors.accent, unfocusedBorderColor = colors.border,
            focusedTextColor = colors.textPrimary, unfocusedTextColor = colors.textPrimary,
            focusedPlaceholderColor = colors.textSecondary, unfocusedPlaceholderColor = colors.textSecondary,
            cursorColor = colors.accent,
        ),
    )
    when {
        !state.hasQuery -> CenteredHint(stringResource(R.string.search_hint))
        state.results.isEmpty() -> CenteredHint(stringResource(R.string.search_no_results, state.query.trim()))
        else -> StyleList(state.results, state.ownedStyleIds, onStyleTapped)
    }
}

@Composable
private fun CenteredHint(text: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(text, style = NorseTheme.type.body, color = NorseTheme.colors.textSecondary, textAlign = TextAlign.Center)
    }
}

@Composable
private fun StyleList(styles: List<IngredientStyle>, ownedStyleIds: Set<UUID>, onStyleTapped: (IngredientStyle) -> Unit) {
    LazyColumn(Modifier.fillMaxSize()) {
        items(styles, key = { it.id }) { style ->
            IngredientRow(style, isInCabinet = style.id in ownedStyleIds, onClick = { onStyleTapped(style) })
            HorizontalDivider(color = NorseTheme.colors.border)
        }
    }
}

// ---- Browse: Category → Family → Style, each level pushed onto the back stack -----------------

@Composable
private fun CategoryList(categories: List<CategoryNode>, onOpen: (CategoryNode) -> Unit) {
    NavigationRows(categories.map { it.category.name }) { onOpen(categories[it]) }
}

@Composable
private fun NavigationRows(labels: List<String>, onClick: (Int) -> Unit) {
    val colors = NorseTheme.colors
    LazyColumn(Modifier.fillMaxSize()) {
        items(labels.size) { index ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button) { onClick(index) }.padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(labels[index], style = NorseTheme.type.heading, color = colors.textPrimary)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = colors.textSecondary)
            }
            HorizontalDivider(color = colors.border)
        }
    }
}

@Composable
fun BrowseFamiliesScreen(
    viewModel: AddIngredientViewModel,
    categoryId: UUID,
    onBack: () -> Unit,
    onOpenFamily: (UUID) -> Unit,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val category = state.taxonomy.category(categoryId)
    val snackbarHostState = remember { SnackbarHostState() }

    FlowScaffold(category?.category?.name.orEmpty(), onBack, snackbarHostState) { modifier ->
        Column(modifier) {
            val families: List<FamilyNode> = category?.families.orEmpty()
            NavigationRows(families.map { it.family.name }) { onOpenFamily(families[it].family.id) }
        }
    }
}

@Composable
fun BrowseStylesScreen(viewModel: AddIngredientViewModel, familyId: UUID, onBack: () -> Unit) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val family = state.taxonomy.family(familyId)
    val snackbarHostState = rememberDuplicateSnackbarState(viewModel)

    FlowScaffold(family?.family?.name.orEmpty(), onBack, snackbarHostState) { modifier ->
        Column(modifier) {
            StyleList(family?.styles.orEmpty(), state.ownedStyleIds, viewModel::onStyleTapped)
        }
    }
}
