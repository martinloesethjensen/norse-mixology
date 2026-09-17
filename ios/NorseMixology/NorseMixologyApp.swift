import SwiftUI
import SwiftData
import NorseMixologyCore

@main
struct NorseMixologyApp: App {
    @State private var taxonomyStore = TaxonomyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(taxonomyStore)
                .task {
                    loadBundledTaxonomyAndLog()
                }
        }
        .modelContainer(for: [CabinetItem.self, FavouriteRecipe.self])
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
            print("⚠️ Bundled taxonomy.json/recipes.json not found")
            return
        }
        do {
            let taxonomyData = try Data(contentsOf: taxonomyURL)
            taxonomyStore.load(taxonomyData: taxonomyData)
            print("Taxonomy loaded: \(taxonomyStore.styleCount) styles")

            taxonomyStore.loadRecipes(from: try Data(contentsOf: recipesURL))
            print("Recipes loaded: \(taxonomyStore.recipes.count) recipes")
        } catch {
            print("⚠️ Failed to load bundled taxonomy/recipes: \(error)")
        }
    }
}
