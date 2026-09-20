import Foundation
import Observation
import SwiftData

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

    public func refresh() {
        favourites = FavouritesService.all(context: modelContext)
        favouritedIds = Set(favourites.map(\.recipeId))
    }
}
