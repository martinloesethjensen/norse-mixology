package dev.martinloeseth.norsemixology.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

/** Stand-in for tabs whose real screens land in a later phase. */
@Composable
fun PlaceholderScreen(title: Int, body: Int) {
    val colors = NorseTheme.colors
    Column(
        Modifier.fillMaxSize().background(colors.background).padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(stringResource(title), style = NorseTheme.type.display, color = colors.textPrimary)
        Text(stringResource(body), style = NorseTheme.type.body, color = colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
    }
}
