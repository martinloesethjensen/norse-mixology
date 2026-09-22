package dev.martinloeseth.norsemixology.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration

/**
 * Material 3's Expanded width breakpoint (>=840dp) — the same threshold
 * `NavigationSuiteScaffold` uses internally to switch from a bottom bar to a rail. Screens that
 * need a two-pane list/detail layout (Recipes, Favourites) check this directly rather than
 * pulling in the full `material3-adaptive` window-size-class artifact for one boolean.
 */
@Composable
fun isExpandedWidth(): Boolean = LocalConfiguration.current.screenWidthDp >= 840
