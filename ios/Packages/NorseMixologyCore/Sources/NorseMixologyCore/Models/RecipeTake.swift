import Foundation
import SwiftData

/// The user's own take on one catalog recipe: a rating and notes (photos are `RecipePhoto`s).
/// Keyed by `recipeId` like `FavouriteRecipe`; `recipeName` is cached so the take stays
/// readable if a later catalog drops the recipe. Never touched by catalog updates.
@Model
public final class RecipeTake {
    public var id: UUID
    // Defaults let SwiftData add this model to existing stores without a custom migration.
    public var recipeId: UUID = UUID()
    public var recipeName: String = ""
    /// 0 = not rated, otherwise 1…5.
    public var rating: Int = 0
    public var notes: String = ""
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), recipeId: UUID, recipeName: String, rating: Int = 0, notes: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.rating = rating
        self.notes = notes
        self.updatedAt = updatedAt
    }
}
