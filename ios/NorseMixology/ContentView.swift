import SwiftUI
import SwiftData
import NorseMixologyCore

enum AppTab: Hashable {
    case recipes, cabinet, favourites
}

/// Root: `TabView` with a `NavigationStack` per screen. The Recipes tab adapts
/// itself to a list/detail split at regular width.
struct ContentView: View {
    @State private var selectedTab: AppTab = .recipes
    @State private var recipeBrowserViewModel = RecipeBrowserViewModel()
    @Environment(TaxonomyStore.self) private var taxonomyStore

    var body: some View {
        if taxonomyStore.isUnavailable {
            ContentUnavailableView(
                "Catalog unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The recipe catalog couldn't be loaded. Reinstalling the app will restore it.")
            )
        } else {
            TabView(selection: $selectedTab) {
                RecipeBrowserView()
                    .tabItem { Label("Recipes", systemImage: "wineglass") }
                    .tag(AppTab.recipes)

                CabinetView(onFindRecipes: { selectedTab = .recipes })
                    .tabItem { Label("Cabinet", systemImage: "archivebox") }
                    .tag(AppTab.cabinet)

                FavouritesView()
                    .tabItem { Label("Favourites", systemImage: "heart") }
                    .tag(AppTab.favourites)
            }
            .environment(recipeBrowserViewModel)
        }
    }
}

#Preview {
    if let container = try? ModelContainer(
        for: CabinetItem.self, FavouriteRecipe.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
        ContentView()
            .environment(TaxonomyStore())
            .environment(FavouritesViewModel(modelContext: container.mainContext))
            .modelContainer(container)
    } else {
        Text("Couldn't create the preview data container")
    }
}
