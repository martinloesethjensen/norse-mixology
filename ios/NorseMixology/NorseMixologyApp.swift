import SwiftUI
import SwiftData
import NorseMixologyCore

@main
struct NorseMixologyApp: App {
    @State private var taxonomyStore = TaxonomyStore()
    @State private var favouritesViewModel: FavouritesViewModel
    private let modelContainer: ModelContainer

    @State private var showOnboardingInitially: Bool

    init() {
        // The container is built explicitly (rather than via `.modelContainer(for:)`)
        // so the app-wide `FavouritesViewModel` can share its main context.
        do {
            let container = try ModelContainer(for: CabinetItem.self, FavouriteRecipe.self)
            modelContainer = container
            _favouritesViewModel = State(initialValue: FavouritesViewModel(modelContext: container.mainContext))
            _showOnboardingInitially = State(initialValue: Self.resolveShowOnboarding(context: container.mainContext))
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showOnboardingInitially: showOnboardingInitially)
                .environment(taxonomyStore)
                .environment(favouritesViewModel)
                .task {
                    await loadCatalog()
                }
        }
        .modelContainer(modelContainer)
    }

    /// Fresh installs see the quiz. An existing install that already has
    /// cabinet or favourite data (but never completed the quiz, since it
    /// predates this phase) silently gets a neutral *completed* profile
    /// instead — only genuinely fresh installs see the onboarding flow.
    private static func resolveShowOnboarding(context: ModelContext) -> Bool {
        let profile = TasteProfileStore.load()
        guard !profile.hasCompletedOnboarding else { return false }

        let hasCabinetItems = ((try? context.fetchCount(FetchDescriptor<CabinetItem>())) ?? 0) > 0
        let hasFavourites = ((try? context.fetchCount(FetchDescriptor<FavouriteRecipe>())) ?? 0) > 0
        guard hasCabinetItems || hasFavourites else { return true }

        TasteProfileStore.save(UserTasteProfile(hasCompletedOnboarding: true))
        return false
    }

    /// Opens (or rebuilds) the on-device catalog off the main thread, then
    /// checks for a newer one in the background — applied on the next launch.
    /// Every scene calls this; `CatalogLaunch.load()` runs the work once per process.
    /// The taxonomy is read-only reference data — it is never written into
    /// SwiftData; only `CabinetItem`s and `FavouriteRecipe`s are persisted.
    @MainActor
    private func loadCatalog() async {
        guard !taxonomyStore.isLoaded else { return }
        let result = await CatalogLaunch.load()
        guard !taxonomyStore.isLoaded else { return }
        switch result {
        case .loaded(let catalog):
            taxonomyStore.load(categories: catalog.categories, recipes: catalog.recipes)
            AppLog.catalog.info("Catalog \(catalog.meta.contentVersion, privacy: .public) (\(catalog.meta.source.rawValue, privacy: .public)) loaded: \(taxonomyStore.styleCount) styles, \(catalog.recipes.count) recipes")
        case .unavailable(let reason):
            AppLog.catalog.error("Catalog unavailable: \(reason, privacy: .public)")
            taxonomyStore.markUnavailable()
        }
    }
}
