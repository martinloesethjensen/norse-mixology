import Foundation
import SwiftData
import NorseMixologyCore

@Observable
final class CabinetViewModel {
    private let modelContext: ModelContext
    private(set) var items: [CabinetItem] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    var isEmpty: Bool { items.isEmpty }

    var groupedItems: [(category: String, items: [CabinetItem])] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return grouped.keys.sorted().map { category in
            (category: category, items: (grouped[category] ?? []).sorted { $0.displayName < $1.displayName })
        }
    }

    func refresh() {
        items = CabinetService.allItems(context: modelContext)
    }

    func contains(styleId: UUID) -> Bool {
        items.contains { $0.ingredientStyleId == styleId }
    }

    func add(_ style: IngredientStyle, taxonomyStore: TaxonomyStore, brand: String? = nil) {
        guard !contains(styleId: style.id) else { return }
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandValue = (trimmedBrand?.isEmpty ?? true) ? nil : trimmedBrand
        let item = CabinetItem(
            ingredientStyleId: style.id,
            ingredientFamilyId: style.familyId,
            categoryId: style.categoryId,
            displayName: brandValue.map { "\($0) \(style.name)" } ?? style.name,
            brand: brandValue,
            style: style.name,
            family: taxonomyStore.familyNamesById[style.familyId] ?? "",
            category: taxonomyStore.categoryNamesById[style.categoryId] ?? "",
            flavorProfile: style.flavorProfile
        )
        CabinetService.add(item, context: modelContext)
        refresh()
    }

    func remove(_ item: CabinetItem) {
        CabinetService.remove(item, context: modelContext)
        refresh()
    }

    /// Runs the matching engine against the current cabinet. Synchronous —
    /// matching ~150 bundled recipes is near-instant on-device, so no
    /// loading state is needed (see Phase 3 notes).
    func findRecipes(taxonomyStore: TaxonomyStore) -> [RecipeMatchResult] {
        let results = RecipeService.findRecipes(
            for: items,
            recipes: taxonomyStore.recipes,
            taxonomyCategories: taxonomyStore.categories
        )
        print("Find Recipes: \(results.count) matches for \(items.count) cabinet item(s)")
        return results
    }
}
