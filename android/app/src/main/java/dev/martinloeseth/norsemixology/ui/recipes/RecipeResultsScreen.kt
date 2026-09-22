package dev.martinloeseth.norsemixology.ui.recipes

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.domain.matching.MatchType
import dev.martinloeseth.norsemixology.domain.matching.RecipeMatchResult
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme
import kotlin.math.roundToInt

/**
 * Stub results list — wires the matching engine end to end. The real Recipe Browser (cards,
 * substitution detail, filters) is Phase 9's job; this only proves the engine's output reaches
 * the UI with the right count and ordering.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecipeResultsScreen(results: List<RecipeMatchResult>, onBack: () -> Unit) {
    val colors = NorseTheme.colors
    Scaffold(
        containerColor = colors.background,
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(stringResource(R.string.recipe_results_title, results.size), style = NorseTheme.type.display.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.navigate_back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background, titleContentColor = colors.textPrimary),
            )
        },
    ) { padding ->
        if (results.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(padding).padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(stringResource(R.string.recipe_results_empty), style = NorseTheme.type.body, color = colors.textSecondary, textAlign = TextAlign.Center)
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(vertical = 8.dp)) {
                items(results, key = { it.recipe.id }) { result -> RecipeResultRow(result) }
            }
        }
    }
}

@Composable
private fun RecipeResultRow(result: RecipeMatchResult) {
    val colors = NorseTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column {
            Text(result.recipe.name, style = NorseTheme.type.heading, color = colors.textPrimary)
            if (result.matchType == MatchType.Partial) {
                Text(
                    stringResource(R.string.recipe_results_substitutions, result.substitutions.size),
                    style = NorseTheme.type.body,
                    color = colors.textSecondary,
                )
            }
        }
        Text("${(result.matchScore * 100).roundToInt()}%", style = NorseTheme.type.body, color = colors.textSecondary)
    }
}
