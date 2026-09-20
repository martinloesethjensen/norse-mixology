import Foundation
import SwiftData

/// A recipe the user has saved. Stores the bundled catalog's `recipeId` plus
/// just enough cached data (`recipeName`) to render a list row even if the
/// recipe were ever removed from a later catalog version.
///
/// See the Data Model doc for the authoritative field list.
@Model
public final class FavouriteRecipe {
    public var id: UUID
    /// The `Recipe.id` in the bundled catalog.
    // The defaults below let SwiftData lightweight-migrate stores created while
    // this was a Phase 0–4 stub with only `id` (new non-optional attributes need one).
    public var recipeId: UUID = UUID()
    public var recipeName: String = ""
    public var dateFavourited: Date = Date()

    public init(id: UUID = UUID(), recipeId: UUID, recipeName: String, dateFavourited: Date = Date()) {
        self.id = id
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.dateFavourited = dateFavourited
    }
}
