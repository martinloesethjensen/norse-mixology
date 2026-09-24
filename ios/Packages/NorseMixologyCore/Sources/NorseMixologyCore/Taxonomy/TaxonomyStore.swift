import Foundation
import Observation

/// In-memory cache of the catalog, loaded once per app launch from the
/// on-device catalog database (see `CatalogBootstrap`). The taxonomy itself is
/// read-only reference data — only `CabinetItem`s (copies of the fields a user
/// picks) are persisted in SwiftData.
@Observable
public final class TaxonomyStore {
    public private(set) var categories: [IngredientCategory] = []
    public private(set) var stylesById: [UUID: IngredientStyle] = [:]
    public private(set) var familyNamesById: [UUID: String] = [:]
    public private(set) var categoryNamesById: [UUID: String] = [:]
    public private(set) var isLoaded = false

    public private(set) var recipes: [Recipe] = []
    public private(set) var recipesLoaded = false

    /// True when no catalog could be loaded at all (spec row 17).
    public private(set) var isUnavailable = false

    public init() {}

    /// No-op if already loaded.
    public func load(categories: [IngredientCategory], recipes: [Recipe]) {
        guard !isLoaded else { return }
        apply(categories)
        self.recipes = recipes
        self.recipesLoaded = true
    }

    public func markUnavailable() {
        isUnavailable = true
    }

    /// No-op if already loaded — safe to call from multiple views without
    /// re-parsing the JSON.
    public func load(taxonomyData: Data) {
        guard !isLoaded else { return }
        guard let categories = try? IngredientTaxonomy.loadCategories(from: taxonomyData) else { return }
        apply(categories)
    }

    private func apply(_ categories: [IngredientCategory]) {
        var familyNames: [UUID: String] = [:]
        var categoryNames: [UUID: String] = [:]
        for category in categories {
            categoryNames[category.id] = category.name
            for family in category.families {
                familyNames[family.id] = family.name
            }
        }

        self.categories = categories
        self.stylesById = IngredientTaxonomy.flattenStyles(categories)
        self.familyNamesById = familyNames
        self.categoryNamesById = categoryNames
        self.isLoaded = true
    }

    /// No-op if already loaded.
    public func loadRecipes(from data: Data) {
        guard !recipesLoaded else { return }
        do {
            let result = try IngredientTaxonomy.loadRecipesReportingSkipped(from: data)
            if result.skippedCount > 0 {
                AppLog.catalog.warning("Skipped \(result.skippedCount) malformed recipe(s) in the bundled catalog")
            }
            self.recipes = result.recipes
            self.recipesLoaded = true
        } catch {
            AppLog.catalog.error("Bundled recipe catalog could not be read: \(error.localizedDescription)")
        }
    }

    public var styleCount: Int { stylesById.count }

    /// Flattened lookup tables over `categories`, for the matching engine.
    public var index: TaxonomyIndex {
        TaxonomyIndex(stylesById: stylesById, familyNamesById: familyNamesById, categoryNamesById: categoryNamesById)
    }
}
