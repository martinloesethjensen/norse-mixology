package dev.martinloeseth.norsemixology.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.data.local.FlavorProfile
import dev.martinloeseth.norsemixology.domain.FlavorLevel
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

/**
 * Five small dots — sweetness, bitterness, smokiness, citrus, herbal, in that order — in the accent
 * colour, stronger for a more pronounced flavour. Read aloud as one element:
 * "Flavour profile: Sweetness: high, Bitterness: low, …". Mirrors the iOS indicator.
 */
@Composable
fun FlavorProfileIndicator(profile: FlavorProfile, modifier: Modifier = Modifier) {
    val dimensions = listOf(
        R.string.flavour_sweetness to profile.sweetness,
        R.string.flavour_bitterness to profile.bitterness,
        R.string.flavour_smokiness to profile.smokiness,
        R.string.flavour_citrus to profile.citrus,
        R.string.flavour_herbal to profile.herbal,
    )
    val summary = dimensions.map { (nameRes, value) ->
        val level = stringResource(
            when (FlavorLevel.of(value)) {
                FlavorLevel.Low -> R.string.flavour_level_low
                FlavorLevel.Medium -> R.string.flavour_level_medium
                FlavorLevel.High -> R.string.flavour_level_high
            },
        )
        stringResource(R.string.flavour_summary_entry, stringResource(nameRes), level)
    }.joinToString(", ")
    val label = stringResource(R.string.flavour_profile)
    val colors = NorseTheme.colors

    Row(
        modifier = modifier.clearAndSetSemantics {
            contentDescription = label
            stateDescription = summary
        },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        dimensions.forEach { (_, value) ->
            Box(
                Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(colors.accent.copy(alpha = (0.15f + value.toFloat() * 0.85f).coerceIn(0f, 1f)))
                    .border(BorderStroke(0.5.dp, colors.border), CircleShape),
            )
        }
    }
}
