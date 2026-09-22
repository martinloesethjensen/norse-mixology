package dev.martinloeseth.norsemixology.ui.cabinet

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.ui.components.FlavorProfileIndicator
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

/** "Confirm" step: shows the picked style and takes an optional brand before it joins the cabinet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfirmIngredientSheet(style: IngredientStyle, onAdd: (brand: String) -> Unit, onDismiss: () -> Unit) {
    val colors = NorseTheme.colors
    var brand by rememberSaveable(style.id.toString()) { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.surfaceRaised,
        contentColor = colors.textPrimary,
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 16.dp).imePadding().navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.confirm_title), style = NorseTheme.type.label, color = colors.textSecondary)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Text(style.name, style = NorseTheme.type.display, color = colors.textPrimary, modifier = Modifier.weight(1f))
                FlavorProfileIndicator(style.flavorProfile)
            }
            if (style.exampleBrands.isNotEmpty()) {
                Text(
                    stringResource(R.string.example_brands, style.exampleBrands.joinToString(", ")),
                    style = NorseTheme.type.body,
                    color = colors.textSecondary,
                )
            }
            OutlinedTextField(
                value = brand,
                onValueChange = { brand = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text(stringResource(R.string.brand_label)) },
                placeholder = { Text(stringResource(R.string.brand_placeholder)) },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = colors.accent, unfocusedBorderColor = colors.border,
                    focusedTextColor = colors.textPrimary, unfocusedTextColor = colors.textPrimary,
                    focusedLabelColor = colors.textSecondary, unfocusedLabelColor = colors.textSecondary,
                    focusedPlaceholderColor = colors.textSecondary, unfocusedPlaceholderColor = colors.textSecondary,
                    cursorColor = colors.accent,
                ),
            )
            Spacer(Modifier.size(4.dp))
            Button(
                onClick = { onAdd(brand) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.onAccent),
            ) { Text(stringResource(R.string.add_to_cabinet)) }
            TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text(stringResource(R.string.cancel), color = colors.textSecondary)
            }
        }
    }
}
