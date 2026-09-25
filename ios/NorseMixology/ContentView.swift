import SwiftUI
import SwiftData
import NorseMixologyCore

enum AppTab: Hashable {
    case recipes, cabinet, favourites, settings
}

/// Root: shows the taste quiz before the first launch's `TabView` (unless an
/// existing install already had cabinet/favourite data — see
/// `NorseMixologyApp.resolveShowOnboarding`), then a `TabView` with a
/// `NavigationStack` per screen. The Recipes tab adapts itself to a
/// list/detail split at regular width.
struct ContentView: View {
    @State private var selectedTab: AppTab = .recipes
    @State private var recipeBrowserViewModel = RecipeBrowserViewModel()
    @State private var showOnboarding: Bool
    @Environment(TaxonomyStore.self) private var taxonomyStore

    init(showOnboardingInitially: Bool) {
        _showOnboarding = State(initialValue: showOnboardingInitially)
    }

    var body: some View {
        Group {
            if taxonomyStore.isUnavailable {
                ContentUnavailableView(
                    "Catalog unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The recipe catalog couldn't be loaded. Reinstalling the app will restore it.")
                )
            } else if showOnboarding {
                TasteOnboardingView { _ in
                    withAnimation { showOnboarding = false }
                }
            } else {
                tabs
            }
        }
        .environment(recipeBrowserViewModel)
    }

    private var tabs: some View {
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

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    if let container = try? ModelContainer(
        for: CabinetItem.self, FavouriteRecipe.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
        ContentView(showOnboardingInitially: false)
            .environment(TaxonomyStore())
            .environment(FavouritesViewModel(modelContext: container.mainContext))
            .modelContainer(container)
    } else {
        Text("Couldn't create the preview data container")
    }
}
