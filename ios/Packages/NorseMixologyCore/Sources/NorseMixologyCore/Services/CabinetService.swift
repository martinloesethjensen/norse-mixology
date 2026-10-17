import Foundation
import SwiftData

/// Thin SwiftData access layer for `CabinetItem` — the view layer (or a
/// view model) owns the `ModelContext` and passes it in per call.
public enum CabinetService {
    public static func add(_ item: CabinetItem, context: ModelContext) {
        context.insert(item)
    }

    /// Adds a brand-less cabinet item for each style not already owned (duplicates in `styles` count once) and returns how many were added.
    /// Backs "I have all of these" on a recipe's missing ingredients.
    @discardableResult
    public static func addAll(_ styles: [IngredientStyle], index: TaxonomyIndex, context: ModelContext, date: Date = Date()) -> Int {
        var owned = Set(allItems(context: context).map(\.ingredientStyleId))
        var added = 0
        for style in styles where owned.insert(style.id).inserted {
            add(CabinetItem.make(from: style, index: index, date: date), context: context)
            added += 1
        }
        return added
    }

    public static func remove(_ item: CabinetItem, context: ModelContext) {
        context.delete(item)
    }

    /// Deletes the cabinet item with this id, if it still exists (used by shopping-list undo). Does not save; the caller saves.
    public static func remove(id: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<CabinetItem>(predicate: #Predicate { $0.id == id })
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
    }

    public static func allItems(context: ModelContext) -> [CabinetItem] {
        let descriptor = FetchDescriptor<CabinetItem>(
            sortBy: [SortDescriptor(\.category), SortDescriptor(\.displayName)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func contains(styleId: UUID, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<CabinetItem>(
            predicate: #Predicate { $0.ingredientStyleId == styleId }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
