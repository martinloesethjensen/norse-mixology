import SwiftUI
import SwiftData
import NorseMixologyCore

/// The Recipes tab: matches for the current cabinet, grouped into Perfect
/// Match / Almost There / Worth Exploring.
///
/// Compact width pushes the detail screen with `NavigationStack`; regular
/// width (iPad) shows results and detail side by side in a
/// `NavigationSplitView`.
struct RecipeBrowserView: View {
    @Environment(RecipeBrowserViewModel.self) private var viewModel
    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .onAppear(perform: refresh)
        // The bundled catalog loads asynchronously at launch; re-match once it lands.
        .onChange(of: taxonomyStore.recipesLoaded) { refresh() }
    }

    private func refresh() {
        viewModel.refresh(context: modelContext, taxonomyStore: taxonomyStore)
    }

    private var stackLayout: some View {
        NavigationStack {
            RecipeResultsList(grouped: viewModel.grouped, interaction: .push, onRefresh: refresh)
                .navigationTitle("Recipes")
                .navigationDestination(for: UUID.self) { id in
                    if let result = viewModel.results.first(where: { $0.id == id }) {
                        RecipeDetailView(result: result, cabinetStyleIds: viewModel.cabinetStyleIds)
                    }
                }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            RecipeResultsList(
                grouped: viewModel.grouped,
                interaction: .select(selectedID: viewModel.selectedRecipeID) { viewModel.selectedRecipeID = $0 },
                onRefresh: refresh
            )
            .navigationTitle("Recipes")
        } detail: {
            if let result = viewModel.selectedEntry?.match {
                RecipeDetailView(result: result, cabinetStyleIds: viewModel.cabinetStyleIds)
                    .id(result.id)
            } else {
                ContentUnavailableView(
                    "Select a Recipe",
                    systemImage: "wineglass",
                    description: Text("Pick a cocktail from the list to see how to make it.")
                )
            }
        }
    }
}
