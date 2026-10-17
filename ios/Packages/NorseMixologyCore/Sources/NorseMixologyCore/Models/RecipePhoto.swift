import Foundation
import SwiftData

/// One photo on a recipe. The ~320 px thumbnail is read by cards and the header;
/// the full image (≤ 1600 px) is stored externally and only read by the viewer.
@Model
public final class RecipePhoto {
    public var id: UUID
    public var recipeId: UUID = UUID()
    public var thumbnail: Data = Data()
    @Attribute(.externalStorage) public var full: Data = Data()
    public var dateAdded: Date = Date()

    public init(id: UUID = UUID(), recipeId: UUID, thumbnail: Data, full: Data, dateAdded: Date = Date()) {
        self.id = id
        self.recipeId = recipeId
        self.thumbnail = thumbnail
        self.full = full
        self.dateAdded = dateAdded
    }
}
