import Foundation
import SwiftData

/// What a restore changed (Backup spec §3).
public struct RestoreResult: Equatable, Sendable {
    public var cabinetAdded = 0
    public var favouritesAdded = 0
    public var shoppingAdded = 0
    public var takesAdded = 0
    public var takesUpdated = 0
    public var photosAdded = 0
    public var photosSkippedForLimit = 0

    public init() {}

    /// Nothing was added or changed ("Already up to date"). Skipped photos are not changes.
    public var isEmpty: Bool {
        cabinetAdded + favouritesAdded + shoppingAdded + takesAdded + takesUpdated + photosAdded == 0
    }
}

/// Merges an opened backup into the store. Nothing on the phone is deleted; the
/// backup only fills gaps. All changes are saved together, and a failed save is
/// rolled back so nothing is half-restored. Restoring the same file twice changes nothing.
public enum BackupMerger {
    public static func merge(_ backup: OpenedBackup, into context: ModelContext,
                             save: (ModelContext) throws -> Void = { try $0.save() }) throws -> RestoreResult {
        let manifest = backup.manifest
        var result = RestoreResult()
        do {
            var cabinetStyles = Set(try context.fetch(FetchDescriptor<CabinetItem>()).map(\.ingredientStyleId))
            for record in manifest.cabinet where !cabinetStyles.contains(record.ingredientStyleId) {
                context.insert(record.makeModel())
                cabinetStyles.insert(record.ingredientStyleId)
                result.cabinetAdded += 1
            }

            var shoppingStyles = Set(try context.fetch(FetchDescriptor<ShoppingItem>()).map(\.ingredientStyleId))
            for record in manifest.shopping
            where !shoppingStyles.contains(record.ingredientStyleId) && !cabinetStyles.contains(record.ingredientStyleId) {
                context.insert(record.makeModel())
                shoppingStyles.insert(record.ingredientStyleId)
                result.shoppingAdded += 1
            }

            var favouriteRecipes = Set(try context.fetch(FetchDescriptor<FavouriteRecipe>()).map(\.recipeId))
            for record in manifest.favourites where !favouriteRecipes.contains(record.recipeId) {
                context.insert(record.makeModel())
                favouriteRecipes.insert(record.recipeId)
                result.favouritesAdded += 1
            }

            var takesByRecipe = Dictionary(try context.fetch(FetchDescriptor<RecipeTake>()).map { ($0.recipeId, $0) },
                                           uniquingKeysWith: { first, _ in first })
            let recipesWithBackupPhotos = Set(manifest.photos.map(\.recipeId))
            for record in manifest.takes {
                if let existing = takesByRecipe[record.recipeId] {
                    guard record.updatedAt > existing.updatedAt else { continue }
                    existing.rating = record.rating
                    existing.notes = record.notes
                    existing.updatedAt = record.updatedAt
                    if existing.recipeName.isEmpty { existing.recipeName = record.recipeName }
                    result.takesUpdated += 1
                } else {
                    let isEmptyTake = record.rating == 0
                        && record.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !recipesWithBackupPhotos.contains(record.recipeId)
                    guard !isEmptyTake else { continue }
                    let take = record.makeModel()
                    context.insert(take)
                    takesByRecipe[record.recipeId] = take
                    result.takesAdded += 1
                }
            }

            var photoDescriptor = FetchDescriptor<RecipePhoto>()
            photoDescriptor.propertiesToFetch = [\.id, \.recipeId]
            let existingPhotos = try context.fetch(photoDescriptor)
            var photoIds = Set(existingPhotos.map(\.id))
            var photoCounts: [UUID: Int] = [:]
            for photo in existingPhotos { photoCounts[photo.recipeId, default: 0] += 1 }
            for record in manifest.photos.sorted(by: { $0.dateAdded < $1.dateAdded }) {
                guard !photoIds.contains(record.id) else { continue }
                guard photoCounts[record.recipeId, default: 0] < TakeLimits.maxPhotos else {
                    result.photosSkippedForLimit += 1
                    continue
                }
                let full = try Data(contentsOf: backup.url(for: record.fullFile))
                let thumbnail = try Data(contentsOf: backup.url(for: record.thumbnailFile))
                context.insert(RecipePhoto(id: record.id, recipeId: record.recipeId, thumbnail: thumbnail, full: full,
                                           dateAdded: record.dateAdded))
                photoIds.insert(record.id)
                photoCounts[record.recipeId, default: 0] += 1
                result.photosAdded += 1
                if takesByRecipe[record.recipeId] == nil {
                    let take = RecipeTake(recipeId: record.recipeId, recipeName: "")
                    context.insert(take)
                    takesByRecipe[record.recipeId] = take
                    result.takesAdded += 1
                }
            }

            guard !result.isEmpty else { return result }
            try save(context)
            AppLog.backup.info("Restored backup: \(result.cabinetAdded) cabinet, \(result.favouritesAdded) favourites, \(result.shoppingAdded) shopping, \(result.takesAdded) takes added, \(result.takesUpdated) updated, \(result.photosAdded) photos")
            return result
        } catch {
            context.rollback()
            let mapped = BackupError.from(error, otherwise: .restoreFailed)
            AppLog.backup.error("Restore failed, rolled back: \(String(describing: mapped), privacy: .public)")
            throw mapped
        }
    }
}
