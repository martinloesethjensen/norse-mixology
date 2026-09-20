import Foundation
import SwiftData

/// SwiftData access layer for `FavouriteRecipe` — the caller owns the
/// `ModelContext` and passes it in per call, like `CabinetService`.
///
/// Every mutation is saved immediately: a favourite is a deliberate, user-visible
/// action, so it shouldn't depend on autosave timing to survive an app kill.
public enum FavouritesService {
    /// No-op if the recipe is already saved, so there is never a duplicate record.
    public static func save(_ recipe: Recipe, context: ModelContext, date: Date = Date()) {
        guard !isFavourited(recipeId: recipe.id, context: context) else { return }
        context.insert(FavouriteRecipe(recipeId: recipe.id, recipeName: recipe.name, dateFavourited: date))
        persist(context)
    }

    public static func remove(recipeId: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<FavouriteRecipe>(predicate: #Predicate { $0.recipeId == recipeId })
        for favourite in (try? context.fetch(descriptor)) ?? [] {
            context.delete(favourite)
        }
        persist(context)
    }

    public static func isFavourited(recipeId: UUID, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<FavouriteRecipe>(predicate: #Predicate { $0.recipeId == recipeId })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Most recently favourited first.
    public static func all(context: ModelContext) -> [FavouriteRecipe] {
        let descriptor = FetchDescriptor<FavouriteRecipe>(sortBy: [SortDescriptor(\.dateFavourited, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Saves the recipe if it isn't a favourite, removes it if it is.
    /// Returns the recipe's new favourited state.
    @discardableResult
    public static func toggle(_ recipe: Recipe, context: ModelContext, date: Date = Date()) -> Bool {
        if isFavourited(recipeId: recipe.id, context: context) {
            remove(recipeId: recipe.id, context: context)
            return false
        } else {
            save(recipe, context: context, date: date)
            return true
        }
    }

    private static func persist(_ context: ModelContext) {
        // A failed explicit save leaves the change pending; SwiftData's autosave retries it.
        try? context.save()
    }
}
