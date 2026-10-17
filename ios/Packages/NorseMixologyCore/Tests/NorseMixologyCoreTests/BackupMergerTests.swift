import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Backup spec §3/§5: restore merges, never deletes, is all-or-nothing, and is
/// safe to repeat.
final class BackupMergerTests: XCTestCase {
    private struct SaveFailure: Error {}

    /// Backs up `source` and opens the file, ready to merge.
    private func backUp(_ source: BackupTestStore) throws -> OpenedBackup {
        let archive = try BackupWriter.write(container: source.container, appVersion: "1.0", temporaryDirectory: try source.scratch())
        return try BackupReader.open(archive, temporaryDirectory: try source.scratch())
    }

    private func opened(_ manifest: BackupManifest, files: [String: Data], in store: BackupTestStore) throws -> OpenedBackup {
        let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(manifest), files: files, in: try store.scratch())
        return try BackupReader.open(archive, temporaryDirectory: try store.scratch())
    }

    func testARoundTripIntoAnEmptyPhoneRestoresEverything() throws {
        let source = try BackupTestStore()
        let (recipeId, photoIds) = try BackupFixtures.populate(ModelContext(source.container))
        let backup = try backUp(source)
        defer { backup.close() }
        let target = try BackupTestStore()
        let context = ModelContext(target.container)

        let result = try BackupMerger.merge(backup, into: context)

        XCTAssertEqual(result.cabinetAdded, 2)
        XCTAssertEqual(result.favouritesAdded, 1)
        XCTAssertEqual(result.shoppingAdded, 1)
        XCTAssertEqual(result.takesAdded, 1)
        XCTAssertEqual(result.photosAdded, 2)
        let fresh = ModelContext(target.container)
        let sourceContext = ModelContext(source.container)
        XCTAssertEqual(Set(try fresh.fetch(FetchDescriptor<CabinetItem>()).map { CabinetRecord($0).ingredientStyleId }),
                       Set(try sourceContext.fetch(FetchDescriptor<CabinetItem>()).map(\.ingredientStyleId)))
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CabinetItem>()).compactMap(\.brand), ["Campari"])
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<FavouriteRecipe>()).map(\.recipeId), [recipeId])
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<ShoppingItem>()).map(\.styleName), ["Sweet Vermouth"])
        let take = try XCTUnwrap(RecipeTakeService.take(for: recipeId, context: fresh))
        XCTAssertEqual(take.rating, 5)
        XCTAssertEqual(take.notes, "Orange peel.")
        XCTAssertEqual(RecipeTakeService.photos(for: recipeId, context: fresh).map(\.id), photoIds)
        XCTAssertEqual(RecipeTakeService.photo(id: photoIds[1], context: fresh)?.full, Data(repeating: 9, count: 5_000))
        XCTAssertEqual(RecipeTakeService.photo(id: photoIds[1], context: fresh)?.thumbnail, Data([3, 4]))
    }

    func testNothingOnThePhoneIsDeletedAndDuplicatesAreSkipped() throws {
        let store = try BackupTestStore()
        let context = ModelContext(store.container)
        let sharedStyle = UUID(), sharedRecipe = UUID()
        let phoneItem = BackupFixtures.cabinetItem(styleId: sharedStyle, name: "Phone Gin")
        context.insert(phoneItem)
        context.insert(FavouriteRecipe(recipeId: sharedRecipe, recipeName: "Negroni"))
        context.insert(ShoppingItem(ingredientStyleId: UUID(), styleName: "Only on phone"))
        try context.save()
        let manifest = BackupManifest(
            appVersion: "1.0", createdAt: BackupFixtures.date(0),
            cabinet: [CabinetRecord(BackupFixtures.cabinetItem(styleId: sharedStyle, name: "Backup Gin")),
                      CabinetRecord(BackupFixtures.cabinetItem(name: "Rum"))],
            favourites: [FavouriteRecord(id: UUID(), recipeId: sharedRecipe, recipeName: "Negroni", dateFavourited: BackupFixtures.date(1)),
                         FavouriteRecord(id: UUID(), recipeId: UUID(), recipeName: "Daiquiri", dateFavourited: BackupFixtures.date(1))])
        let backup = try opened(manifest, files: [:], in: store)
        defer { backup.close() }

        let result = try BackupMerger.merge(backup, into: context)

        XCTAssertEqual(result.cabinetAdded, 1)
        XCTAssertEqual(result.favouritesAdded, 1)
        let fresh = ModelContext(store.container)
        XCTAssertEqual(Set(try fresh.fetch(FetchDescriptor<CabinetItem>()).map(\.displayName)), ["Phone Gin", "Rum"])
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<FavouriteRecipe>()), 2)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<ShoppingItem>()).map(\.styleName), ["Only on phone"])
    }

    func testAShoppingItemAlreadyInTheCabinetIsNotAdded() throws {
        let store = try BackupTestStore()
        let style = UUID()
        let context = ModelContext(store.container)
        context.insert(BackupFixtures.cabinetItem(styleId: style))
        try context.save()
        let manifest = BackupManifest(appVersion: "1.0", createdAt: BackupFixtures.date(0),
                                      shopping: [ShoppingRecord(id: UUID(), ingredientStyleId: style, styleName: "Campari", dateAdded: BackupFixtures.date(1))])
        let backup = try opened(manifest, files: [:], in: store)
        defer { backup.close() }

        XCTAssertEqual(try BackupMerger.merge(backup, into: context).shoppingAdded, 0)
    }

    func testTheNewerTakeWins() throws {
        let store = try BackupTestStore()
        let older = UUID(), newer = UUID()
        let context = ModelContext(store.container)
        context.insert(RecipeTake(recipeId: older, recipeName: "A", rating: 2, notes: "phone", updatedAt: BackupFixtures.date(10)))
        context.insert(RecipeTake(recipeId: newer, recipeName: "B", rating: 2, notes: "phone", updatedAt: BackupFixtures.date(50)))
        try context.save()
        let manifest = BackupManifest(appVersion: "1.0", createdAt: BackupFixtures.date(0), takes: [
            TakeRecord(id: UUID(), recipeId: older, recipeName: "A", rating: 5, notes: "backup", updatedAt: BackupFixtures.date(20)),
            TakeRecord(id: UUID(), recipeId: newer, recipeName: "B", rating: 5, notes: "backup", updatedAt: BackupFixtures.date(20)),
        ])
        let backup = try opened(manifest, files: [:], in: store)
        defer { backup.close() }

        let result = try BackupMerger.merge(backup, into: context)

        XCTAssertEqual(result.takesUpdated, 1)
        let fresh = ModelContext(store.container)
        XCTAssertEqual(RecipeTakeService.take(for: older, context: fresh)?.notes, "backup", "backup was newer")
        XCTAssertEqual(RecipeTakeService.take(for: newer, context: fresh)?.notes, "phone", "phone was newer")
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<RecipeTake>()), 2, "no second take per recipe")
    }

    func testPhotosAreCombinedUpToTheLimit() throws {
        let store = try BackupTestStore()
        let recipeId = UUID()
        let context = ModelContext(store.container)
        context.insert(RecipeTake(recipeId: recipeId, recipeName: "A", rating: 4))
        var phonePhotoIds: [UUID] = []
        for index in 0..<4 {
            let photo = RecipePhoto(recipeId: recipeId, thumbnail: Data([1]), full: Data([1]), dateAdded: BackupFixtures.date(Double(index)))
            context.insert(photo)
            phonePhotoIds.append(photo.id)
        }
        try context.save()
        var photos: [PhotoRecord] = []
        var files: [String: Data] = [:]
        // One photo the phone already has, then four new ones: two fit, two are over the limit.
        for (index, id) in ([phonePhotoIds[0]] + (0..<4).map { _ in UUID() }).enumerated() {
            let paths = PhotoRecord.paths(for: id)
            photos.append(PhotoRecord(id: id, recipeId: recipeId, dateAdded: BackupFixtures.date(Double(100 + index)),
                                      fullFile: paths.full, thumbnailFile: paths.thumbnail))
            files[paths.full] = Data([2])
            files[paths.thumbnail] = Data([2])
        }
        let backup = try opened(BackupManifest(appVersion: "1.0", createdAt: BackupFixtures.date(0), photos: photos), files: files, in: store)
        defer { backup.close() }

        let result = try BackupMerger.merge(backup, into: context)

        XCTAssertEqual(result.photosAdded, 2)
        XCTAssertEqual(result.photosSkippedForLimit, 2)
        XCTAssertEqual(RecipeTakeService.photos(for: recipeId, context: ModelContext(store.container)).count, TakeLimits.maxPhotos)
    }

    func testRestoringTheSameFileTwiceChangesNothing() throws {
        let source = try BackupTestStore()
        try BackupFixtures.populate(ModelContext(source.container))
        let backup = try backUp(source)
        defer { backup.close() }
        let target = try BackupTestStore()

        XCTAssertFalse(try BackupMerger.merge(backup, into: ModelContext(target.container)).isEmpty)
        let second = try BackupMerger.merge(backup, into: ModelContext(target.container))

        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(try ModelContext(target.container).fetchCount(FetchDescriptor<RecipePhoto>()), 2)
    }

    func testATakeForARecipeNoLongerInTheCatalogIsRestored() throws {
        let store = try BackupTestStore()
        let gone = BackupFixtures.validManifest(recipeId: UUID(), notes: "Loved it")
        let backup = try opened(gone.manifest, files: gone.files, in: store)
        defer { backup.close() }

        let result = try BackupMerger.merge(backup, into: ModelContext(store.container))

        XCTAssertEqual(result.takesAdded, 1)
        XCTAssertEqual(RecipeTakeService.take(for: gone.manifest.takes[0].recipeId, context: ModelContext(store.container))?.recipeName,
                       "Daiquiri")
    }

    func testAnEmptyTakeIsNotCreated() throws {
        let store = try BackupTestStore()
        let manifest = BackupManifest(appVersion: "1.0", createdAt: BackupFixtures.date(0), takes: [
            TakeRecord(id: UUID(), recipeId: UUID(), recipeName: "A", rating: 0, notes: "  ", updatedAt: BackupFixtures.date(1)),
        ])
        let backup = try opened(manifest, files: [:], in: store)
        defer { backup.close() }

        XCTAssertTrue(try BackupMerger.merge(backup, into: ModelContext(store.container)).isEmpty)
        XCTAssertEqual(try ModelContext(store.container).fetchCount(FetchDescriptor<RecipeTake>()), 0)
    }

    func testAFailedSaveRollsBackSoNothingChanges() throws {
        let source = try BackupTestStore()
        try BackupFixtures.populate(ModelContext(source.container))
        let backup = try backUp(source)
        defer { backup.close() }
        let target = try BackupTestStore()
        let context = ModelContext(target.container)
        context.insert(BackupFixtures.cabinetItem(name: "Already here"))
        try context.save()

        XCTAssertThrowsError(try BackupMerger.merge(backup, into: context, save: { _ in throw SaveFailure() })) { error in
            XCTAssertEqual(error as? BackupError, .restoreFailed)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<CabinetItem>()).map(\.displayName), ["Already here"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecipePhoto>()), 0)
        XCTAssertEqual(try ModelContext(target.container).fetchCount(FetchDescriptor<RecipeTake>()), 0)
    }
}
