import Foundation
import SwiftData

/// Thin SwiftData access layer for `CabinetItem` — the view layer (or a
/// view model) owns the `ModelContext` and passes it in per call.
public enum CabinetService {
    public static func add(_ item: CabinetItem, context: ModelContext) {
        context.insert(item)
    }

    public static func remove(_ item: CabinetItem, context: ModelContext) {
        context.delete(item)
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
