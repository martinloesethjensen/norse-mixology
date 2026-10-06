import Foundation
import SwiftUI
import SwiftData
import UIKit
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
        let item = CabinetItem.make(from: style, index: taxonomyStore.index, brand: brand)
        CabinetService.add(item, context: modelContext)
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
            refresh()
        }
    }

    func remove(_ item: CabinetItem) {
        CabinetService.remove(item, context: modelContext)
        refresh()
    }
}
