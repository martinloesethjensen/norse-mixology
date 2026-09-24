import SwiftUI
import SwiftData
import NorseMixologyCore

@main
struct NorseMixologyApp: App {
    @State private var taxonomyStore = TaxonomyStore()
    @State private var favouritesViewModel: FavouritesViewModel
    private let modelContainer: ModelContainer

    init() {
        // The container is built explicitly (rather than via `.modelContainer(for:)`)
        // so the app-wide `FavouritesViewModel` can share its main context.
        do {
            let container = try ModelContainer(for: CabinetItem.self, FavouriteRecipe.self)
            modelContainer = container
            _favouritesViewModel = State(initialValue: FavouritesViewModel(modelContext: container.mainContext))
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(taxonomyStore)
                .environment(favouritesViewModel)
                .task {
                    await loadCatalog()
                }
        }
        .modelContainer(modelContainer)
    }

    /// Opens (or rebuilds) the on-device catalog off the main thread, then
    /// checks for a newer one in the background — applied on the next launch.
    /// The taxonomy is read-only reference data — it is never written into
    /// SwiftData; only `CabinetItem`s and `FavouriteRecipe`s are persisted.
    @MainActor
    private func loadCatalog() async {
        guard !taxonomyStore.isLoaded else { return }
        let result = await Task.detached(priority: .userInitiated) { CatalogLaunch.bootstrap() }.value
        switch result {
        case .loaded(let catalog):
            taxonomyStore.load(categories: catalog.categories, recipes: catalog.recipes)
            AppLog.catalog.info("Catalog \(catalog.meta.contentVersion, privacy: .public) (\(catalog.meta.source.rawValue, privacy: .public)): \(taxonomyStore.styleCount) styles, \(catalog.recipes.count) recipes")
            let meta = catalog.meta
            Task.detached(priority: .background) { await CatalogLaunch.refresh(current: meta) }
        case .unavailable(let reason):
            AppLog.catalog.error("Catalog unavailable: \(reason, privacy: .public)")
            taxonomyStore.markUnavailable()
        }
    }
}
