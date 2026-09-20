import SwiftUI
import SwiftData
import NorseMixologyCore

/// The Favourites tab: saved recipes, most recently favourited first.
/// Rows open the full recipe from the bundled catalog — always available
/// offline, no loading state.
struct FavouritesView: View {
    @Environment(FavouritesViewModel.self) private var viewModel
    @Environment(TaxonomyStore.self) private var taxonomyStore
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isEmpty {
                    ContentUnavailableView(
                        "No Favourites Yet",
                        systemImage: "heart",
                        description: Text("Recipes you love will appear here")
                    )
                } else {
                    favouritesList
                }
            }
            .dsScreenBackground()
            .navigationTitle("Favourites")
            .navigationDestination(for: UUID.self) { recipeId in
                if let recipe = taxonomyStore.recipes.first(where: { $0.id == recipeId }) {
                    FavouriteRecipeDetail(recipe: recipe)
                } else {
                    ContentUnavailableView(
                        "Recipe Unavailable",
                        systemImage: "wineglass",
                        description: Text("This recipe is no longer available.")
                    )
                }
            }
        }
    }

    private var favouritesList: some View {
        let recipesById = Dictionary(taxonomyStore.recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return List {
            ForEach(viewModel.favourites) { favourite in
                row(for: favourite, recipe: recipesById[favourite.recipeId])
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.remove(favourite)
                        } label: {
                            Label("Unfavourite", systemImage: "heart.slash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .dsListBackground()
    }

    @ViewBuilder
    private func row(for favourite: FavouriteRecipe, recipe: Recipe?) -> some View {
        if let recipe {
            Button {
                path.append(recipe.id)
            } label: {
                FavouriteRowView(name: favourite.recipeName, recipe: recipe, dateFavourited: favourite.dateFavourited)
            }
            .buttonStyle(.plain)
        } else {
            // The recipe is no longer in the bundled catalog: keep the cached row so it can still be removed.
            FavouriteRowView(name: favourite.recipeName, recipe: nil, dateFavourited: favourite.dateFavourited)
                .opacity(0.6)
        }
    }
}

private struct FavouriteRowView: View {
    let name: String
    let recipe: Recipe?
    let dateFavourited: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer(minLength: 8)
                if let recipe {
                    Image(systemName: recipe.glassType.symbolName)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .accessibilityLabel("\(recipe.glassType.displayName) glass")
                }
            }

            HStack(spacing: 8) {
                if let recipe {
                    OutlinePillView(text: recipe.difficulty.displayName)
                } else {
                    Text("This recipe is no longer available")
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer(minLength: 8)
                Text("Favourited \(dateFavourited.formatted(date: .abbreviated, time: .omitted))")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DesignTokens.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Detail for a favourite. Availability is worked out against the cabinet as it
/// is right now; a recipe the cabinet can no longer make simply has no match.
private struct FavouriteRecipeDetail: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var modelContext
    @Environment(TaxonomyStore.self) private var taxonomyStore

    var body: some View {
        let cabinet = CabinetService.allItems(context: modelContext)
        RecipeDetailView(
            recipe: recipe,
            match: RecipeService.matchResult(for: recipe, cabinet: cabinet, taxonomyCategories: taxonomyStore.categories),
            cabinetStyleIds: Set(cabinet.map(\.ingredientStyleId))
        )
    }
}
