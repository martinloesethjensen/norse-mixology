import Foundation
import Observation

/// In-memory cache of the bundled taxonomy, loaded once per app launch.
/// The taxonomy itself is read-only reference data — it is never written
/// into SwiftData; only `CabinetItem`s (copies of the fields a user picks)
/// are persisted.
@Observable
public final class TaxonomyStore {
    public private(set) var categories: [IngredientCategory] = []
    public private(set) var stylesById: [UUID: IngredientStyle] = [:]
    public private(set) var familyNamesById: [UUID: String] = [:]
    public private(set) var categoryNamesById: [UUID: String] = [:]
    public private(set) var isLoaded = false

    public init() {}

    /// No-op if already loaded — safe to call from multiple views without
    /// re-parsing the bundled JSON.
    public func load(taxonomyData: Data) {
        guard !isLoaded else { return }
        guard let categories = try? IngredientTaxonomy.loadCategories(from: taxonomyData) else { return }

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

    public var styleCount: Int { stylesById.count }
}
