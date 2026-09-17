import SwiftUI

/// Compact-width root: `TabView` + `NavigationStack` per screen.
/// `NavigationSplitView` for regular width (iPad) lands in Phase 6.
struct ContentView: View {
    var body: some View {
        TabView {
            RecipesPlaceholderView()
                .tabItem { Label("Recipes", systemImage: "wineglass") }

            CabinetView()
                .tabItem { Label("Cabinet", systemImage: "archivebox") }

            FavouritesPlaceholderView()
                .tabItem { Label("Favourites", systemImage: "heart") }
        }
    }
}

#Preview {
    ContentView()
}
