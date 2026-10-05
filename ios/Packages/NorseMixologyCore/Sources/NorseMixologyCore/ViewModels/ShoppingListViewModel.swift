import Foundation
import Observation
import SwiftData

/// A shopping-list item paired with its catalog style; `style` is nil when a
/// later catalog dropped it (a "ghost" — shown by cached name, not tickable).
public struct ShoppingEntry: Identifiable {
    public let item: ShoppingItem
    public let style: IngredientStyle?

    public var id: UUID { item.ingredientStyleId }
}

public enum ShoppingAddResult: Equatable, Sendable {
    case added, alreadyListed, alreadyOwned
}

/// What a tick-off did, so it can be undone exactly.
public struct BoughtReceipt: Equatable, Sendable {
    public let styleId: UUID
    public let styleName: String
    /// The cabinet item the tick created; nil when the bottle was already owned.
    public let createdCabinetItemId: UUID?
}

/// App-wide shopping-list state (Shopping List spec §2). One instance is
/// injected at the app root, like `FavouritesViewModel`, so the Cabinet tab,
/// the Shopping list screen and the recipe screen always agree.
///
/// Lives in the core package so its rules are unit-testable without a simulator.
@Observable
public final class ShoppingListViewModel {
    private let modelContext: ModelContext

    /// Most recently added first.
    public private(set) var items: [ShoppingItem] = []
    public private(set) var listedStyleIds: Set<UUID> = []

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    public var isEmpty: Bool { items.isEmpty }

    public func contains(styleId: UUID) -> Bool {
        listedStyleIds.contains(styleId)
    }

    @discardableResult
    public func add(_ style: IngredientStyle, cabinetStyleIds: Set<UUID>) -> ShoppingAddResult {
        if cabinetStyleIds.contains(style.id) { return .alreadyOwned }
        if listedStyleIds.contains(style.id) { return .alreadyListed }
        ShoppingService.add(styleId: style.id, styleName: style.name, context: modelContext)
        refresh()
        return .added
    }

    /// Adds every style that isn't owned or already listed; returns how many were added.
    @discardableResult
    public func addAll(_ styles: [IngredientStyle], cabinetStyleIds: Set<UUID>) -> Int {
        var seen = listedStyleIds.union(cabinetStyleIds)
        var added = 0
        for style in styles where !seen.contains(style.id) {
            ShoppingService.add(styleId: style.id, styleName: style.name, context: modelContext)
            seen.insert(style.id)
            added += 1
        }
        if added > 0 { refresh() }
        return added
    }

    public func remove(_ item: ShoppingItem) {
        remove(styleId: item.ingredientStyleId)
    }

    public func remove(styleId: UUID) {
        ShoppingService.remove(styleId: styleId, context: modelContext)
        refresh()
    }

    /// Drops items whose bottle is now in the cabinet, however it got there.
    public func pruneOwned(cabinetStyleIds: Set<UUID>) {
        let owned = listedStyleIds.intersection(cabinetStyleIds)
        guard !owned.isEmpty else { return }
        for styleId in owned {
            ShoppingService.remove(styleId: styleId, context: modelContext)
        }
        refresh()
    }

    /// Each item, in `items` order, with its catalog style or nil.
    public func entries(in index: TaxonomyIndex) -> [ShoppingEntry] {
        items.map { ShoppingEntry(item: $0, style: index.stylesById[$0.ingredientStyleId]) }
    }

    /// Moves the item into the cabinet, then off the list. The cabinet insert is
    /// saved first, so an interruption can only leave the bottle on both (which
    /// `pruneOwned` repairs), never on neither. Returns nil for a ghost item.
    public func markBought(_ item: ShoppingItem, index: TaxonomyIndex, date: Date = Date()) -> BoughtReceipt? {
        guard let style = index.stylesById[item.ingredientStyleId] else { return nil }

        var createdId: UUID?
        if !CabinetService.contains(styleId: style.id, context: modelContext) {
            let cabinetItem = CabinetItem.make(from: style, index: index, date: date)
            CabinetService.add(cabinetItem, context: modelContext)
            createdId = cabinetItem.id
            try? modelContext.save()
        }
        ShoppingService.remove(styleId: style.id, context: modelContext)
        refresh()
        return BoughtReceipt(styleId: style.id, styleName: style.name, createdCabinetItemId: createdId)
    }

    /// Reverses `markBought`: removes the cabinet item it created (if it still
    /// exists) and puts the item back on the list.
    public func undo(_ receipt: BoughtReceipt) {
        if let createdId = receipt.createdCabinetItemId {
            CabinetService.remove(id: createdId, context: modelContext)
            try? modelContext.save()
        }
        // No-op if the item was already re-added; the cabinet removal above is saved either way.
        ShoppingService.add(styleId: receipt.styleId, styleName: receipt.styleName, context: modelContext)
        refresh()
    }

    public func refresh() {
        items = ShoppingService.all(context: modelContext)
        listedStyleIds = Set(items.map(\.ingredientStyleId))
    }
}
