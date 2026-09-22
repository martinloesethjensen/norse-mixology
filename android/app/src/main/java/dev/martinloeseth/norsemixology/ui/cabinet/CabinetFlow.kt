package dev.martinloeseth.norsemixology.ui.cabinet

import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import dev.martinloeseth.norsemixology.AppContainer
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable data object CabinetKey : NavKey
@Serializable data object AddIngredientKey : NavKey
@Serializable data class BrowseFamiliesKey(val categoryId: String) : NavKey
@Serializable data class BrowseStylesKey(val familyId: String) : NavKey

/**
 * The Cabinet tab's navigation: Cabinet → Add Ingredient → Browse (Category → Family → Style).
 * Every screen of the add flow shares one [AddIngredientViewModel] (scoped to the activity, and
 * reset when the flow opens), so the confirmation sheet — hosted here, above the whole back stack —
 * works the same whether the style was picked from Search or from Browse.
 */
@Composable
fun CabinetFlow(container: AppContainer) {
    val backStack = rememberNavBackStack(CabinetKey)
    val activity = LocalActivity.current as ComponentActivity
    val addViewModel: AddIngredientViewModel = viewModel(
        viewModelStoreOwner = activity,
        factory = viewModelFactory { initializer { AddIngredientViewModel(container.taxonomy, container.cabinetRepository) } },
    )
    val addState by addViewModel.uiState.collectAsStateWithLifecycle()

    NavDisplay(
        backStack = backStack,
        onBack = { backStack.removeLastOrNull() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            rememberViewModelStoreNavEntryDecorator(),
        ),
        entryProvider = entryProvider {
            entry<CabinetKey> {
                val viewModel: CabinetViewModel = viewModel(
                    factory = viewModelFactory { initializer { CabinetViewModel(container.cabinetRepository) } },
                )
                CabinetScreen(
                    viewModel = viewModel,
                    onAddIngredient = {
                        addViewModel.reset()
                        backStack.add(AddIngredientKey)
                    },
                )
            }
            entry<AddIngredientKey> {
                AddIngredientScreen(
                    viewModel = addViewModel,
                    onBack = { backStack.removeLastOrNull() },
                    onOpenCategory = { backStack.add(BrowseFamiliesKey(it.toString())) },
                )
            }
            entry<BrowseFamiliesKey> { key ->
                BrowseFamiliesScreen(
                    viewModel = addViewModel,
                    categoryId = UUID.fromString(key.categoryId),
                    onBack = { backStack.removeLastOrNull() },
                    onOpenFamily = { backStack.add(BrowseStylesKey(it.toString())) },
                )
            }
            entry<BrowseStylesKey> { key ->
                BrowseStylesScreen(
                    viewModel = addViewModel,
                    familyId = UUID.fromString(key.familyId),
                    onBack = { backStack.removeLastOrNull() },
                )
            }
        },
    )

    addState.pendingStyle?.let { style ->
        ConfirmIngredientSheet(
            style = style,
            onAdd = { brand ->
                addViewModel.confirm(brand) {
                    // Back to the Cabinet, whatever depth of Browse we were at.
                    while (backStack.size > 1) backStack.removeLastOrNull()
                }
            },
            onDismiss = addViewModel::dismissConfirmation,
        )
    }
}
