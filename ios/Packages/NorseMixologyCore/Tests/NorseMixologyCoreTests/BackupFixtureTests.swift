import XCTest
import SwiftData
@testable import NorseMixologyCore

/// A committed version 1 backup, written by `BackupWriter` from `BackupFixtures.populate`.
/// If this breaks, backups people already saved no longer restore.
final class BackupFixtureTests: XCTestCase {
    func testTheVersion1FixtureStillRestores() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "backup-v1", withExtension: "nmbackup"))
        let store = try BackupTestStore()
        let backup = try BackupReader.open(fixture, temporaryDirectory: try store.scratch())
        defer { backup.close() }

        XCTAssertEqual(backup.summary, BackupSummary(createdAt: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-19T12:00:00Z")),
                                                     cabinetItems: 2, favourites: 1, shoppingItems: 1, takes: 1, photos: 2))

        let result = try BackupMerger.merge(backup, into: ModelContext(store.container))
        XCTAssertEqual(result.photosAdded, 2)

        let context = ModelContext(store.container)
        let cabinet = try context.fetch(FetchDescriptor<CabinetItem>())
        XCTAssertEqual(Set(cabinet.map(\.displayName)), ["Campari", "Gin"])
        XCTAssertEqual(cabinet.compactMap(\.brand), ["Campari"])
        XCTAssertEqual(cabinet.first?.flavorProfile, BackupFixtures.flavor)
        let favourite = try XCTUnwrap(context.fetch(FetchDescriptor<FavouriteRecipe>()).first)
        XCTAssertEqual(favourite.recipeName, "Negroni")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingItem>()).map(\.styleName), ["Sweet Vermouth"])
        let take = try XCTUnwrap(RecipeTakeService.take(for: favourite.recipeId, context: context))
        XCTAssertEqual(take.rating, 5)
        XCTAssertEqual(take.notes, "Orange peel.")
        XCTAssertEqual(take.updatedAt, BackupFixtures.date(4))

        let photos = RecipeTakeService.photos(for: favourite.recipeId, context: context)
        XCTAssertEqual(photos.map(\.dateAdded), [BackupFixtures.date(5), BackupFixtures.date(6)])
        let sizes = try photos.map { try XCTUnwrap(TestImages.pixelSize(of: XCTUnwrap(RecipeTakeService.photo(id: $0.id, context: context)?.full))) }
        XCTAssertEqual(sizes.map(\.width), [64, 80])
        XCTAssertEqual(photos.compactMap { TestImages.pixelSize(of: $0.thumbnail)?.width }, [32, 40])
    }
}
