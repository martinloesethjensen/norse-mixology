package dev.martinloeseth.norsemixology.ui.recipes

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForwardIos
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.data.local.Recipe
import dev.martinloeseth.norsemixology.data.local.RecipeIngredient
import dev.martinloeseth.norsemixology.domain.Taxonomy
import dev.martinloeseth.norsemixology.domain.displayName
import dev.martinloeseth.norsemixology.domain.matching.AvailabilityStatus
import dev.martinloeseth.norsemixology.domain.matching.MatchBadgeState
import dev.martinloeseth.norsemixology.domain.matching.RecipeAvailability
import dev.martinloeseth.norsemixology.domain.matching.RecipeMatchResult
import dev.martinloeseth.norsemixology.domain.matching.SubstitutionDetail
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme
import java.util.UUID

/**
 * Full recipe: header, ingredients with cabinet availability, substitution notes, and method steps.
 * [match] is null for a recipe the current cabinet can't make (reachable from Favourites).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecipeDetailScreen(
    recipe: Recipe,
    ingredients: List<RecipeIngredient>,
    match: RecipeMatchResult?,
    cabinetStyleIds: Set<UUID>,
    taxonomy: Taxonomy,
    isFavourite: Boolean,
    onToggleFavourite: () -> Unit,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = NorseTheme.colors
    val substitutions = match?.substitutions.orEmpty()

    Scaffold(
        modifier = modifier,
        containerColor = colors.background,
        topBar = {
            CenterAlignedTopAppBar(
                title = {},
                navigationIcon = {
                    onBack?.let {
                        IconButton(onClick = it) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.navigate_back)) }
                    }
                },
                actions = {
                    IconButton(onClick = onToggleFavourite) {
                        Icon(
                            if (isFavourite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                            tint = if (isFavourite) colors.accent else colors.textSecondary,
                            contentDescription = stringResource(if (isFavourite) R.string.remove_from_favourites else R.string.add_to_favourites),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            Header(recipe, match)

            if (recipe.description.isNotEmpty()) {
                Text(recipe.description, style = NorseTheme.type.body, color = colors.textSecondary)
            }

            IngredientsSection(match, ingredients, cabinetStyleIds, taxonomy)

            if (substitutions.isNotEmpty()) {
                SubstitutionCallout(substitutions)
            }

            if (recipe.steps.isNotEmpty()) {
                MethodSection(recipe.steps)
            }

            Spacer(Modifier.size(1.dp))
        }
    }
}

@Composable
private fun Header(recipe: Recipe, match: RecipeMatchResult?) {
    val colors = NorseTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(recipe.glassType.icon, contentDescription = stringResource(R.string.glass_content_description, recipe.glassType.displayName), tint = colors.textSecondary)
            Text(recipe.name, style = NorseTheme.type.display, color = colors.textPrimary)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinePill(recipe.method.displayName)
            OutlinePill(recipe.difficulty.displayName)
            if (match != null) {
                MatchBadge(MatchBadgeState.of(match))
            } else {
                OutlinePill(stringResource(R.string.missing_ingredients_pill))
            }
        }
    }
}

@Composable
private fun SectionHeading(title: String) {
    Text(title, style = NorseTheme.type.heading, color = NorseTheme.colors.textPrimary)
}

@Composable
private fun IngredientsSection(match: RecipeMatchResult?, ingredients: List<RecipeIngredient>, cabinetStyleIds: Set<UUID>, taxonomy: Taxonomy) {
    val rows = if (match != null) {
        RecipeAvailability.rows(match, cabinetStyleIds)
    } else {
        RecipeAvailability.rows(ingredients, emptyList(), cabinetStyleIds)
    }
    val unknownIngredient = stringResource(R.string.unknown_ingredient)
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionHeading(stringResource(R.string.ingredients_heading))
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            rows.forEach { row ->
                val name = row.substitution?.required?.name
                    ?: taxonomy.stylesById[row.ingredient.ingredientStyleId]?.name
                    ?: unknownIngredient
                IngredientRow(name = name, ingredient = row.ingredient, status = row.status, substitute = row.substitution)
            }
        }
    }
}

@Composable
private fun IngredientRow(name: String, ingredient: RecipeIngredient, status: AvailabilityStatus, substitute: SubstitutionDetail?) {
    val colors = NorseTheme.colors
    var isExpanded by remember { mutableStateOf(false) }
    val rotation by animateFloatAsState(if (isExpanded) 90f else 0f, label = "chevron")

    val (icon, statusColor, statusLabel) = when (status) {
        AvailabilityStatus.Exact -> Triple(Icons.Filled.CheckCircle, colors.matchExact, stringResource(R.string.ingredient_status_exact))
        AvailabilityStatus.Substituted -> Triple(Icons.Filled.Autorenew, colors.matchSubstituted, stringResource(R.string.ingredient_status_substituted))
        AvailabilityStatus.Unavailable -> Triple(Icons.Filled.Cancel, colors.matchUnavailable, stringResource(R.string.ingredient_status_unavailable))
    }

    Column(
        Modifier
            .fillMaxWidth()
            .let { base -> if (substitute != null) base.clickable(onClickLabel = if (isExpanded) stringResource(R.string.hide_substitution_note) else stringResource(R.string.show_substitution_note)) { isExpanded = !isExpanded } else base }
            .let { base ->
                val rowDescription = stringResource(R.string.ingredient_row_content_description, name, statusLabel)
                base.semantics { contentDescription = rowDescription }
            },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, contentDescription = null, tint = statusColor, modifier = Modifier.size(22.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(name, style = NorseTheme.type.heading, color = if (status == AvailabilityStatus.Unavailable) colors.textSecondary else colors.textPrimary)
                Text(detailLine(ingredient, stringResource(R.string.optional_suffix)), style = NorseTheme.type.body, color = colors.textSecondary)
                if (substitute != null) {
                    Text(stringResource(R.string.using_substitute, substitute.substitute.name), style = NorseTheme.type.body, color = colors.matchSubstituted)
                }
            }
            if (substitute != null) {
                Icon(Icons.AutoMirrored.Filled.ArrowForwardIos, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(14.dp).rotate(rotation))
            }
        }
        if (substitute != null) {
            AnimatedVisibility(visible = isExpanded) {
                Column(Modifier.padding(start = 34.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(substitute.note, style = NorseTheme.type.body, color = colors.textSecondary)
                    substitute.ratioHint?.let { Text(it, style = NorseTheme.type.body, color = colors.textSecondary) }
                }
            }
        }
    }
}

/** "60ml, freshly squeezed · optional" */
private fun detailLine(ingredient: RecipeIngredient, optionalSuffix: String): String {
    val parts = mutableListOf(ingredient.amount)
    if (!ingredient.preparation.isNullOrEmpty()) parts += ingredient.preparation
    var line = parts.joinToString(", ")
    if (ingredient.isOptional) line += optionalSuffix
    return line
}

@Composable
private fun SubstitutionCallout(substitutions: List<SubstitutionDetail>) {
    val colors = NorseTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.surfaceRaised, RoundedCornerShape(14.dp))
            .border(1.dp, colors.matchSubstituted.copy(alpha = 0.5f), RoundedCornerShape(14.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(stringResource(R.string.substitutions_heading), style = NorseTheme.type.heading, color = colors.matchSubstituted)
        substitutions.forEach { sub ->
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(R.string.using_instead_of, sub.substitute.name, sub.required.name), style = NorseTheme.type.heading, color = colors.textPrimary)
                Text(sub.note, style = NorseTheme.type.body, color = colors.textSecondary)
                sub.ratioHint?.let { Text(it, style = NorseTheme.type.body, color = colors.textSecondary) }
            }
        }
    }
}

@Composable
private fun MethodSection(steps: List<String>) {
    val colors = NorseTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionHeading(stringResource(R.string.method_heading))
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            steps.forEachIndexed { index, step ->
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Box(
                        Modifier.size(22.dp).border(1.dp, colors.border, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("${index + 1}", style = NorseTheme.type.label, color = colors.textSecondary)
                    }
                    val stepDescription = stringResource(R.string.step_content_description, index + 1, step)
                    Text(
                        step,
                        style = NorseTheme.type.heading.copy(fontWeight = FontWeight.Normal),
                        color = colors.textPrimary,
                        modifier = Modifier.weight(1f).semantics { contentDescription = stepDescription },
                    )
                }
            }
        }
    }
}
