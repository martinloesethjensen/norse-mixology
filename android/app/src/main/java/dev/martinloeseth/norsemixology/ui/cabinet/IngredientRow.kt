package dev.martinloeseth.norsemixology.ui.cabinet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.ui.components.FlavorProfileIndicator
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

/**
 * A taxonomy style in Search results / Browse. Ingredients already in the cabinet are greyed out
 * with a check but stay tappable, so tapping one can explain that it's already there.
 */
@Composable
fun IngredientRow(style: IngredientStyle, isInCabinet: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = NorseTheme.colors
    val ownedLabel = stringResource(R.string.in_cabinet_state)

    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { if (isInCabinet) stateDescription = ownedLabel }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f).alpha(if (isInCabinet) 0.5f else 1f)) {
            Text(style.name, style = NorseTheme.type.heading, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (style.exampleBrands.isNotEmpty()) {
                Text(
                    style.exampleBrands.take(2).joinToString(", "),
                    style = NorseTheme.type.body,
                    color = colors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        FlavorProfileIndicator(style.flavorProfile, Modifier.alpha(if (isInCabinet) 0.5f else 1f))
        if (isInCabinet) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = colors.matchExact, modifier = Modifier.size(24.dp))
        }
    }
}
