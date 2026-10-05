import Foundation
import SwiftData

/// SwiftData access layer for `ShoppingItem` — the caller owns the
/// `ModelContext`, like `CabinetService` and `FavouritesService`.
///
/// Every mutation is saved immediately: `save()` also flushes any pending
/// cabinet insert in the same context, which the tick-off ordering relies on.
public enum ShoppingService {
    /// No-op if the style is already listed, so there is never a duplicate.
    public static func add(styleId: UUID, styleName: String, context: ModelContext, date: Date = Date()) {
        guard !contains(styleId: styleId, context: context) else { return }
        context.insert(ShoppingItem(ingredientStyleId: styleId, styleName: styleName, dateAdded: date))
        persist(context)
    }

    public static func remove(styleId: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.ingredientStyleId == styleId })
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
        persist(context)
    }

    public static func contains(styleId: UUID, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.ingredientStyleId == styleId })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Most recently added first.
    public static func all(context: ModelContext) -> [ShoppingItem] {
        let descriptor = FetchDescriptor<ShoppingItem>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func persist(_ context: ModelContext) {
        // A failed explicit save leaves the change pending; SwiftData's autosave retries it.
        try? context.save()
    }
}
