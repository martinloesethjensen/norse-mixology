import Foundation
import SwiftData

public enum TakeError: Error, Equatable, Sendable {
    case invalidRating
    case photoLimitReached
    /// The change is still pending in the context; autosave will retry it.
    case saveFailed
}

/// SwiftData access for `RecipeTake` and `RecipePhoto` — the caller owns the
/// `ModelContext`, like `FavouritesService`. Every change is saved immediately;
/// a failed save is thrown, never swallowed. A take with no rating, no notes
/// and no photos is deleted, so there are never empty records.
public enum RecipeTakeService {
    public static func take(for recipeId: UUID, context: ModelContext) -> RecipeTake? {
        let descriptor = FetchDescriptor<RecipeTake>(predicate: #Predicate { $0.recipeId == recipeId })
        return (try? context.fetch(descriptor))?.first
    }

    /// 0 clears the rating; anything outside 0…5 or off the half-star grid is rejected, not clamped.
    public static func setRating(_ rating: Double, for recipe: Recipe, context: ModelContext, date: Date = Date()) throws {
        guard TakeLimits.isValidRating(rating) else { throw TakeError.invalidRating }
        if rating == 0, take(for: recipe.id, context: context) == nil { return }
        let take = ensureTake(for: recipe, context: context)
        take.rating = rating
        take.updatedAt = date
        try finish(recipe.id, context: context)
    }

    /// Trimmed to `TakeLimits.maxNotesLength`; whitespace-only counts as empty.
    public static func setNotes(_ notes: String, for recipe: Recipe, context: ModelContext, date: Date = Date()) throws {
        let limited = String(notes.prefix(TakeLimits.maxNotesLength))
        let stored = limited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : limited
        if stored.isEmpty, take(for: recipe.id, context: context) == nil { return }
        let take = ensureTake(for: recipe, context: context)
        take.notes = stored
        take.updatedAt = date
        try finish(recipe.id, context: context)
    }

    @discardableResult
    public static func addPhoto(full: Data, thumbnail: Data, for recipe: Recipe, context: ModelContext, date: Date = Date()) throws -> UUID {
        guard photoCount(recipe.id, context: context) < TakeLimits.maxPhotos else { throw TakeError.photoLimitReached }
        let take = ensureTake(for: recipe, context: context)
        take.updatedAt = date
        let photo = RecipePhoto(recipeId: recipe.id, thumbnail: thumbnail, full: full, dateAdded: date)
        context.insert(photo)
        do {
            try finish(recipe.id, context: context)
        } catch {
            // Don't leave the failed photo pending: it would show in the strip and be saved later.
            context.delete(photo)
            if let pending = Self.take(for: recipe.id, context: context),
               pending.rating == 0, pending.notes.isEmpty, photoCount(recipe.id, context: context) == 0 {
                context.delete(pending)
            }
            throw error
        }
        return photo.id
    }

    public static func removePhoto(id: UUID, context: ModelContext) throws {
        guard let photo = photo(id: id, context: context) else { return }
        let recipeId = photo.recipeId
        context.delete(photo)
        try finish(recipeId, context: context)
    }

    public static func photo(id: UUID, context: ModelContext) -> RecipePhoto? {
        let descriptor = FetchDescriptor<RecipePhoto>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Oldest first. Loads thumbnails but not the full images (those are read on demand by `photo(id:)`).
    public static func photos(for recipeId: UUID, context: ModelContext) -> [RecipePhoto] {
        var descriptor = FetchDescriptor<RecipePhoto>(
            predicate: #Predicate { $0.recipeId == recipeId },
            sortBy: [SortDescriptor(\.dateAdded)]
        )
        descriptor.propertiesToFetch = [\.id, \.recipeId, \.thumbnail, \.dateAdded]
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Lists (read by cards and rows, so no per-row queries)

    public static func ratings(context: ModelContext) -> [UUID: Double] {
        let descriptor = FetchDescriptor<RecipeTake>(predicate: #Predicate { $0.rating > 0 })
        let takes = (try? context.fetch(descriptor)) ?? []
        return Dictionary(takes.map { ($0.recipeId, $0.rating) }, uniquingKeysWith: { first, _ in first })
    }

    public static func recipeIdsWithNotes(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<RecipeTake>(predicate: #Predicate { $0.notes != "" })
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.recipeId))
    }

    public static func photoCounts(context: ModelContext) -> [UUID: Int] {
        var descriptor = FetchDescriptor<RecipePhoto>()
        descriptor.propertiesToFetch = [\.recipeId]
        var counts: [UUID: Int] = [:]
        for photo in (try? context.fetch(descriptor)) ?? [] {
            counts[photo.recipeId, default: 0] += 1
        }
        return counts
    }

    // MARK: - Internals

    private static func ensureTake(for recipe: Recipe, context: ModelContext) -> RecipeTake {
        if let existing = take(for: recipe.id, context: context) { return existing }
        let take = RecipeTake(recipeId: recipe.id, recipeName: recipe.name)
        context.insert(take)
        return take
    }

    private static func photoCount(_ recipeId: UUID, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<RecipePhoto>(predicate: #Predicate { $0.recipeId == recipeId })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Deletes the take when nothing is left in it, then saves.
    private static func finish(_ recipeId: UUID, context: ModelContext) throws {
        if let take = take(for: recipeId, context: context),
           take.rating == 0, take.notes.isEmpty, photoCount(recipeId, context: context) == 0 {
            context.delete(take)
        }
        do {
            try context.save()
        } catch {
            throw TakeError.saveFailed
        }
    }
}
