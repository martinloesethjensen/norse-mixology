package dev.martinloeseth.norsemixology.ui.recipes

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.Color
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.domain.matching.MatchBadgeState
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

/** Filled pill communicating how completely the cabinet covers a recipe (lime = exact, gold = substituted). */
@Composable
fun MatchBadge(state: MatchBadgeState, modifier: Modifier = Modifier) {
    val colors = NorseTheme.colors
    val (label, color) = when (state) {
        MatchBadgeState.Exact -> stringResource(R.string.match_badge_exact) to colors.matchExact
        is MatchBadgeState.Substituted -> pluralStringResource(R.plurals.match_badge_substituted, state.count, state.count) to colors.matchSubstituted
    }
    Text(
        label.uppercase(),
        style = NorseTheme.type.label,
        color = colors.onAccent,
        modifier = modifier
            .background(color, CircleShape)
            .padding(horizontal = 9.dp, vertical = 4.dp),
    )
}

/** Small outlined pill for secondary facts (difficulty, substituted ingredient). */
@Composable
fun OutlinePill(text: String, modifier: Modifier = Modifier, tint: Color = NorseTheme.colors.textSecondary, uppercase: Boolean = true) {
    Text(
        if (uppercase) text.uppercase() else text,
        style = NorseTheme.type.label,
        color = tint,
        modifier = modifier
            .border(1.dp, tint.copy(alpha = 0.6f), CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}
