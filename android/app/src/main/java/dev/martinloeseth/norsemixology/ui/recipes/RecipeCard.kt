package dev.martinloeseth.norsemixology.ui.recipes

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.domain.displayName
import dev.martinloeseth.norsemixology.domain.matching.MatchBadgeState
import dev.martinloeseth.norsemixology.domain.matching.RecipeMatchResult
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

private val CardShape = RoundedCornerShape(14.dp)

/** A single result in the Recipe Browser: name, glass, method/difficulty, and how well the cabinet covers it. */
@Composable
fun RecipeCard(result: RecipeMatchResult, isFavourited: Boolean, modifier: Modifier = Modifier, isSelected: Boolean = false) {
    val colors = NorseTheme.colors
    val recipe = result.recipe

    Column(
        modifier
            .fillMaxWidth()
            .background(colors.surfaceRaised, CardShape)
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) colors.accent else colors.border, CardShape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(recipe.name, style = NorseTheme.type.heading, color = colors.textPrimary, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (isFavourited) {
                Icon(Icons.Filled.Favorite, contentDescription = stringResource(R.string.favourite_content_description), tint = colors.accent)
            }
            Icon(recipe.glassType.icon, contentDescription = stringResource(R.string.glass_content_description, recipe.glassType.displayName), tint = colors.textSecondary)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(recipe.method.displayName, style = NorseTheme.type.body, color = colors.textSecondary)
            OutlinePill(recipe.difficulty.displayName)
        }

        MatchBadge(MatchBadgeState.of(result))

        result.substitutions.firstOrNull()?.let { sub ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinePill(
                    stringResource(R.string.substituted_ingredient_pill, sub.substitute.name, sub.required.name),
                    tint = colors.matchSubstituted,
                    uppercase = false,
                )
                if (result.substitutions.size > 1) {
                    val moreCount = result.substitutions.size - 1
                    Text(pluralStringResource(R.plurals.more_substitutions, moreCount, moreCount), style = NorseTheme.type.body, color = colors.textSecondary)
                }
            }
        }
    }
}
