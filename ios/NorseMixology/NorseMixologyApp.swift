import SwiftUI
import SwiftData
import NorseMixologyCore

@main
struct NorseMixologyApp: App {
    init() {
        NorseMixologyApp.loadBundledTaxonomyAndLog()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [CabinetItem.self, FavouriteRecipe.self])
    }

    /// Phase 1 only parses and logs the bundled catalog — seeding it into
    /// SwiftData happens in Phase 2 (Cabinet) / Phase 5 (Favourites).
    private static func loadBundledTaxonomyAndLog() {
        guard
            let taxonomyURL = Bundle.main.url(forResource: "taxonomy", withExtension: "json"),
            let recipesURL = Bundle.main.url(forResource: "recipes", withExtension: "json")
        else {
            print("⚠️ Bundled taxonomy.json/recipes.json not found")
            return
        }
        do {
            let categories = try IngredientTaxonomy.loadCategories(from: Data(contentsOf: taxonomyURL))
            let styleCount = categories.reduce(0) { $0 + $1.families.reduce(0) { $0 + $1.styles.count } }
            print("Taxonomy loaded: \(styleCount) styles")

            let recipes = try IngredientTaxonomy.loadRecipes(from: Data(contentsOf: recipesURL))
            print("Recipes loaded: \(recipes.count) recipes")
        } catch {
            print("⚠️ Failed to load bundled taxonomy/recipes: \(error)")
        }
    }
}
