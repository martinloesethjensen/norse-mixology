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
                    loadBundledTaxonomyAndLog()
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

    /// Loads the bundled catalog into `taxonomyStore` (used by Cabinet/Add
    /// Ingredient) and logs the counts the Phase 1 verification checklist
    /// wants. The taxonomy itself is read-only reference data — it is never
    /// written into SwiftData; only `CabinetItem`s (Phase 2) and
    /// `FavouriteRecipe`s (Phase 5) are persisted.
    private func loadBundledTaxonomyAndLog() {
        guard
            let taxonomyURL = Bundle.main.url(forResource: "taxonomy", withExtension: "json"),
            let recipesURL = Bundle.main.url(forResource: "recipes", withExtension: "json")
        else {
            AppLog.catalog.error("Bundled taxonomy.json/recipes.json not found")
            return
        }
        do {
            let taxonomyData = try Data(contentsOf: taxonomyURL)
            taxonomyStore.load(taxonomyData: taxonomyData)
            AppLog.catalog.info("Taxonomy loaded: \(taxonomyStore.styleCount) styles")

            taxonomyStore.loadRecipes(from: try Data(contentsOf: recipesURL))
            AppLog.catalog.info("Recipes loaded: \(taxonomyStore.recipes.count) recipes")
        } catch {
            AppLog.catalog.error("Failed to load bundled taxonomy/recipes: \(error.localizedDescription)")
        }
    }
}
