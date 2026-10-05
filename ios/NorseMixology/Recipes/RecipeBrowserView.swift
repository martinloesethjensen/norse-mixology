import SwiftUI
import SwiftData
import NorseMixologyCore

/// The Recipes tab: Can make (matches for the current cabinet, grouped into
/// Perfect Match / Almost There / Worth Exploring) or All recipes (the whole
/// catalog grouped by how much is missing). Search and filters apply to both.
///
/// Compact width pushes the detail screen with `NavigationStack`; regular
/// width (iPad) shows list and detail side by side in a `NavigationSplitView`.
struct RecipeBrowserView: View {
    @Environment(RecipeBrowserViewModel.self) private var viewModel
    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Remembered across launches; search text and filters deliberately are not.
    @SceneStorage("recipes.browseMode") private var storedMode = RecipeBrowseState.Mode.canMake.rawValue
    @State private var isPresentingFilters = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .onAppear {
            if let mode = RecipeBrowseState.Mode(rawValue: storedMode) {
                viewModel.browseState.mode = mode
            }
            refresh()
        }
        // The bundled catalog loads asynchronously at launch; re-match once it lands.
        .onChange(of: taxonomyStore.recipesLoaded) { refresh() }
        .onChange(of: viewModel.browseState) {
            storedMode = viewModel.browseState.mode.rawValue
            viewModel.clearSelectionIfHidden()
        }
        .sheet(isPresented: $isPresentingFilters) {
            RecipeFilterSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func refresh() {
        viewModel.refresh(context: modelContext, taxonomyStore: taxonomyStore)
    }

    private var stackLayout: some View {
        NavigationStack {
            browser(interaction: .push)
                .navigationDestination(for: UUID.self) { id in
                    detail(for: id)
                }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            browser(interaction: .select(selectedID: viewModel.selectedRecipeID) { viewModel.selectedRecipeID = $0 })
        } detail: {
            if let id = viewModel.selectedRecipeID {
                detail(for: id)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "Select a Recipe",
                    systemImage: "wineglass",
                    description: Text("Pick a cocktail from the list to see how to make it.")
                )
            }
        }
    }

    @ViewBuilder
    private func detail(for id: UUID) -> some View {
        if let result = viewModel.entry(for: id)?.match {
            RecipeDetailView(result: result, cabinetStyleIds: viewModel.cabinetStyleIds)
        } else if let entry = viewModel.entry(for: id) {
            RecipeDetailView(recipe: entry.recipe, match: nil, cabinetStyleIds: viewModel.cabinetStyleIds)
        } else {
            ContentUnavailableView("This recipe is no longer available", systemImage: "wineglass")
        }
    }

    private func browser(interaction: RecipeResultsList.Interaction) -> some View {
        @Bindable var viewModel = viewModel
        return list(interaction: interaction)
            .safeAreaInset(edge: .top, spacing: 0) { BrowseHeader() }
            .searchable(text: $viewModel.browseState.filter.query, prompt: Text("Recipes or ingredients"))
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let active = !viewModel.browseState.filter.criteria.isEmpty
                    Button {
                        isPresentingFilters = true
                    } label: {
                        Label("Filters", systemImage: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityValue(active ? Text("\(viewModel.browseState.filter.criteria.count) active") : Text("None active"))
                }
            }
    }

    @ViewBuilder
    private func list(interaction: RecipeResultsList.Interaction) -> some View {
        switch viewModel.browseState.mode {
        case .canMake:
            // An empty cabinet keeps RecipeResultsList's own empty message.
            if !viewModel.grouped.isEmpty && viewModel.visibleGrouped.isEmpty {
                NoMatchingRecipesView(onClear: clearFilters)
            } else {
                RecipeResultsList(grouped: viewModel.visibleGrouped, interaction: interaction, onRefresh: refresh)
            }
        case .all:
            if viewModel.visibleAvailability.isEmpty, !viewModel.browseState.filter.isEmpty {
                NoMatchingRecipesView(onClear: clearFilters)
            } else {
                CatalogList(grouped: viewModel.visibleAvailability, interaction: interaction, onRefresh: refresh)
            }
        }
    }

    private func clearFilters() {
        viewModel.browseState.filter.clear()
    }
}
