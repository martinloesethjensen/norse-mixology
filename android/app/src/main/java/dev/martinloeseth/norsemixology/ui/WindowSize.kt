package dev.martinloeseth.norsemixology.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp

/**
 * Material 3's Expanded width breakpoint (>=840dp) — the same threshold
 * `NavigationSuiteScaffold` uses internally to switch from a bottom bar to a rail. Screens that
 * need a two-pane list/detail layout (Recipes, Favourites) check this directly rather than
 * pulling in the full `material3-adaptive` window-size-class artifact for one boolean.
 *
 * Uses `LocalWindowInfo`'s container size rather than `Configuration.screenWidthDp`, which can
 * report the whole-device size rather than the window actually available to the app (e.g. in
 * multi-window mode).
 */
@Composable
fun isExpandedWidth(): Boolean {
    val density = LocalDensity.current
    val widthPx = LocalWindowInfo.current.containerSize.width
    return with(density) { widthPx.toDp() } >= 840.dp
}
