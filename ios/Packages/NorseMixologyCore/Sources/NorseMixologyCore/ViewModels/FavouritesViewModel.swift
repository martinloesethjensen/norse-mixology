import Foundation
import Observation
import SwiftData

/// A favourite paired with its recipe in the current catalog. `recipe` is nil
/// when the catalog no longer has it; the row then shows the cached name.
public struct FavouriteEntry: Identifiable {
    public let favourite: FavouriteRecipe
    public let recipe: Recipe?

    public var id: UUID { favourite.recipeId }
}

/// App-wide favourites state. One instance is injected at the app root so the
/// heart in the recipe detail, the heart on result cards, and the Favourites
/// tab always agree.
///
/// Lives in the core package (rather than the app target) so its behaviour can
/// be unit-tested without a simulator.
@Observable
public final class FavouritesViewModel {
    private let modelContext: ModelContext

    /// Most recently favourited first.
    public private(set) var favourites: [FavouriteRecipe] = []
    private var favouritedIds: Set<UUID> = []

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    public var isEmpty: Bool { favourites.isEmpty }

    public func isFavourited(_ recipeId: UUID) -> Bool {
        favouritedIds.contains(recipeId)
    }

    /// Returns the recipe's new favourited state.
    @discardableResult
    public func toggle(_ recipe: Recipe, date: Date = Date()) -> Bool {
        let isNowFavourited = FavouritesService.toggle(recipe, context: modelContext, date: date)
        refresh()
        return isNowFavourited
    }

    public func remove(_ favourite: FavouriteRecipe) {
        FavouritesService.remove(recipeId: favourite.recipeId, context: modelContext)
        refresh()
    }

    /// Each favourite, in `favourites` order, with its catalog recipe or nil.
    public func entries(in recipes: [Recipe]) -> [FavouriteEntry] {
        let recipesById = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return favourites.map { FavouriteEntry(favourite: $0, recipe: recipesById[$0.recipeId]) }
    }

    public func refresh() {
        favourites = FavouritesService.all(context: modelContext)
        favouritedIds = Set(favourites.map(\.recipeId))
    }
}
