import Foundation
import SwiftData

/// An ingredient the user wants to buy — one per catalog `IngredientStyle`.
/// `styleName` is cached so the row still renders if a later catalog drops
/// the style (Shopping List spec §2).
@Model
public final class ShoppingItem {
    public var id: UUID
    // Defaults let SwiftData add this model to existing stores without a custom migration.
    public var ingredientStyleId: UUID = UUID()
    public var styleName: String = ""
    public var dateAdded: Date = Date()

    public init(id: UUID = UUID(), ingredientStyleId: UUID, styleName: String, dateAdded: Date = Date()) {
        self.id = id
        self.ingredientStyleId = ingredientStyleId
        self.styleName = styleName
        self.dateAdded = dateAdded
    }
}
