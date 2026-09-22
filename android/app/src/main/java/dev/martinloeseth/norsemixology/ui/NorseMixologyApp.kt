package dev.martinloeseth.norsemixology.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Kitchen
import androidx.compose.material.icons.filled.LocalBar
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import dev.martinloeseth.norsemixology.AppContainer
import dev.martinloeseth.norsemixology.R
import dev.martinloeseth.norsemixology.ui.cabinet.CabinetFlow
import dev.martinloeseth.norsemixology.ui.theme.NorseTheme

private enum class AppTab(val label: Int, val icon: ImageVector) {
    Recipes(R.string.tab_recipes, Icons.Filled.LocalBar),
    Cabinet(R.string.tab_cabinet, Icons.Filled.Kitchen),
    Favourites(R.string.tab_favourites, Icons.Filled.Favorite),
}

/**
 * Top-level shell. `NavigationSuiteScaffold` picks the chrome from the window size — a bottom bar
 * on phones, a navigation rail on tablets — while the destinations stay identical.
 */
@Composable
fun NorseMixologyApp(container: AppContainer) {
    val colors = NorseTheme.colors
    var tab by rememberSaveable { mutableStateOf(AppTab.Cabinet) }

    val itemColors = NavigationSuiteDefaults.itemColors()
    NavigationSuiteScaffold(
        navigationSuiteItems = {
            AppTab.entries.forEach { entry ->
                item(
                    selected = tab == entry,
                    onClick = { tab = entry },
                    icon = { Icon(entry.icon, contentDescription = null) },
                    label = { Text(stringResource(entry.label), style = NorseTheme.type.label) },
                )
            }
        },
        containerColor = colors.background,
        navigationSuiteColors = NavigationSuiteDefaults.colors(
            navigationBarContainerColor = colors.surface,
            navigationBarContentColor = colors.textPrimary,
            navigationRailContainerColor = colors.surface,
            navigationRailContentColor = colors.textPrimary,
        ),
    ) {
        when (tab) {
            AppTab.Recipes -> PlaceholderScreen(R.string.recipes_placeholder_title, R.string.recipes_placeholder_body)
            AppTab.Cabinet -> CabinetFlow(container)
            AppTab.Favourites -> PlaceholderScreen(R.string.favourites_placeholder_title, R.string.favourites_placeholder_body)
        }
    }
}
