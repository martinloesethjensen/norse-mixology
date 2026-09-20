import SwiftUI
import SwiftData
import NorseMixologyCore

enum AppTab: Hashable {
    case recipes, cabinet, favourites
}

/// Root: `TabView` with a `NavigationStack` per screen. The Recipes tab adapts
/// itself to a list/detail split at regular width; the app-wide iPad shell
/// (sidebar replacing the tab bar) lands in Phase 6.
struct ContentView: View {
    @State private var selectedTab: AppTab = .recipes
    @State private var recipeBrowserViewModel = RecipeBrowserViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            RecipeBrowserView()
                .tabItem { Label("Recipes", systemImage: "wineglass") }
                .tag(AppTab.recipes)

            CabinetView(onFindRecipes: { selectedTab = .recipes })
                .tabItem { Label("Cabinet", systemImage: "archivebox") }
                .tag(AppTab.cabinet)

            FavouritesPlaceholderView()
                .tabItem { Label("Favourites", systemImage: "heart") }
                .tag(AppTab.favourites)
        }
        .environment(recipeBrowserViewModel)
    }
}

#Preview {
    ContentView()
        .environment(TaxonomyStore())
        .modelContainer(for: [CabinetItem.self, FavouriteRecipe.self], inMemory: true)
}
