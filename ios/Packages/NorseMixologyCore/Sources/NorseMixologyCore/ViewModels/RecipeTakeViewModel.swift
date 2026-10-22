import Foundation
import Observation
import SwiftData

public struct PhotoItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let thumbnail: Data
}

public struct AddPhotosResult: Equatable, Sendable {
    public var added: Int
    public var failed: Int
    public var refusedForLimit: Int

    public init(added: Int = 0, failed: Int = 0, refusedForLimit: Int = 0) {
        self.added = added
        self.failed = failed
        self.refusedForLimit = refusedForLimit
    }
}

/// App-wide state for the user's takes (Recipe Take spec §2). One instance is
/// injected at the app root, like `FavouritesViewModel`. The dictionaries are
/// what cards and rows read, so a list never queries the database per row.
/// `@MainActor` because it owns main-context writes and processes photos off
/// the main actor before applying them.
@MainActor
@Observable
public final class RecipeTakeViewModel {
    private let modelContext: ModelContext

    public private(set) var ratings: [UUID: Double] = [:]
    public private(set) var hasNotes: Set<UUID> = []
    public private(set) var photoCounts: [UUID: Int] = [:]
    /// The last failure, for the screen to report; cleared by `clearError()`.
    public private(set) var lastError: TakeError?

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    public func refresh() {
        // Assign only on change: every notes save calls this, and an equal
        // assignment would still invalidate observers.
        let newRatings = RecipeTakeService.ratings(context: modelContext)
        if newRatings != ratings { ratings = newRatings }
        let newHasNotes = RecipeTakeService.recipeIdsWithNotes(context: modelContext)
        if newHasNotes != hasNotes { hasNotes = newHasNotes }
        let newCounts = RecipeTakeService.photoCounts(context: modelContext)
        if newCounts != photoCounts { photoCounts = newCounts }
    }

    public func clearError() { lastError = nil }

    // MARK: - Rating

    public func rating(for recipeId: UUID) -> Double { ratings[recipeId] ?? 0 }

    /// Tapping the value that is already the rating clears it.
    public func setRating(_ tapped: Double, for recipe: Recipe) {
        let target = tapped == rating(for: recipe.id) ? 0 : tapped
        perform { try RecipeTakeService.setRating(target, for: recipe, context: modelContext) }
    }

    // MARK: - Notes

    public func notes(for recipeId: UUID) -> String {
        RecipeTakeService.take(for: recipeId, context: modelContext)?.notes ?? ""
    }

    public func setNotes(_ notes: String, for recipe: Recipe) {
        perform { try RecipeTakeService.setNotes(notes, for: recipe, context: modelContext) }
    }

    // MARK: - Photos

    public func photos(for recipeId: UUID) -> [PhotoItem] {
        RecipeTakeService.photos(for: recipeId, context: modelContext).map { PhotoItem(id: $0.id, thumbnail: $0.thumbnail) }
    }

    public func fullImage(id: UUID) -> Data? {
        RecipeTakeService.photo(id: id, context: modelContext)?.full
    }

    public func removePhoto(id: UUID) {
        perform { try RecipeTakeService.removePhoto(id: id, context: modelContext) }
    }

    /// Processes the picked photos off the main actor, then stores the readable
    /// ones (up to the free slots). Nothing is dropped silently: the result counts
    /// what was added, what could not be read, and what the limit refused.
    public func addPhotos(_ items: [Data], for recipe: Recipe) async -> AddPhotosResult {
        let free = max(0, TakeLimits.maxPhotos - (photoCounts[recipe.id] ?? 0))
        let accepted = Array(items.prefix(free))
        var result = AddPhotosResult(refusedForLimit: items.count - accepted.count)

        let processed: [(full: Data, thumbnail: Data)?] = await Task.detached(priority: .userInitiated) {
            accepted.map { try? PhotoProcessor.process($0) }
        }.value

        for entry in processed {
            guard let entry else {
                result.failed += 1
                continue
            }
            do {
                try RecipeTakeService.addPhoto(full: entry.full, thumbnail: entry.thumbnail, for: recipe, context: modelContext)
                result.added += 1
            } catch TakeError.photoLimitReached {
                result.refusedForLimit += 1
            } catch let error as TakeError {
                lastError = error
                result.failed += 1
            } catch {
                lastError = .saveFailed
                result.failed += 1
            }
        }
        refresh()
        return result
    }

    // MARK: - Internals

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch let error as TakeError {
            lastError = error
        } catch {
            lastError = .saveFailed
        }
        refresh()
    }
}
