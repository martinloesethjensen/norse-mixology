import Foundation
import SwiftData

/// Replaces all user data with a validated backup in one save (Backup spec §3).
/// The caller owns the `ModelContext`; the app passes its main context so the
/// views see the result at once. On any error the store and preferences are unchanged.
public enum BackupRestorer {
    public static func restore(_ contents: BackupContents, context: ModelContext, defaults: UserDefaults = .standard) throws {
        try restore(contents, context: context, defaults: defaults) { try $0.save() }
    }

    /// `save` is a seam for the rollback test.
    static func restore(
        _ contents: BackupContents, context: ModelContext, defaults: UserDefaults,
        save: (ModelContext) throws -> Void
    ) throws {
        let data = contents.data

        // Everything that can fail on its own happens before the store is touched.
        // Mapped, so a large photo set isn't read into memory up front.
        var images: [UUID: (full: Data, thumbnail: Data)] = [:]
        for photo in data.photos {
            guard let files = contents.photoFiles[photo.id],
                  let full = try? Data(contentsOf: files.full, options: .mappedIfSafe),
                  let thumbnail = try? Data(contentsOf: files.thumbnail, options: .mappedIfSafe) else {
                throw BackupError.damaged("missing extracted photo")
            }
            images[photo.id] = (full, thumbnail)
        }

        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }

        do {
            // One by one rather than `delete(model:)`, which bypasses the pending changes `rollback()` undoes.
            try context.fetch(FetchDescriptor<CabinetItem>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<FavouriteRecipe>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<ShoppingItem>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<RecipeTake>()).forEach { context.delete($0) }
            var photoDescriptor = FetchDescriptor<RecipePhoto>()
            photoDescriptor.propertiesToFetch = [\.id]
            try context.fetch(photoDescriptor).forEach { context.delete($0) }

            for item in data.cabinetItems {
                context.insert(CabinetItem(
                    id: item.id, ingredientStyleId: item.ingredientStyleId, ingredientFamilyId: item.ingredientFamilyId,
                    categoryId: item.categoryId, displayName: item.displayName, brand: item.brand, style: item.style,
                    family: item.family, category: item.category, flavorProfile: item.flavorProfile, dateAdded: item.dateAdded))
            }
            for favourite in data.favourites {
                context.insert(FavouriteRecipe(
                    id: favourite.id, recipeId: favourite.recipeId, recipeName: favourite.recipeName,
                    dateFavourited: favourite.dateFavourited))
            }
            for item in data.shoppingItems {
                context.insert(ShoppingItem(id: item.id, ingredientStyleId: item.ingredientStyleId, styleName: item.styleName,
                                            dateAdded: item.dateAdded))
            }
            for take in data.takes {
                context.insert(RecipeTake(id: take.id, recipeId: take.recipeId, recipeName: take.recipeName,
                                          rating: take.rating, notes: take.notes, updatedAt: take.updatedAt))
            }
            for photo in data.photos {
                let image = images[photo.id]!
                context.insert(RecipePhoto(id: photo.id, recipeId: photo.recipeId, thumbnail: image.thumbnail,
                                           full: image.full, dateAdded: photo.dateAdded))
            }

            try save(context)
        } catch {
            context.rollback()
            throw BackupError.saveFailed
        }

        TasteProfileStore.save(data.preferences.tasteProfile, defaults: defaults)
        PantryStore.save(Set(data.preferences.pantryStaples.compactMap(PantryStaple.init(rawValue:))), defaults: defaults)
    }
}
