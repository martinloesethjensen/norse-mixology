import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Backup spec §2: every stored field survives model → record → JSON → record → model.
final class BackupManifestTests: XCTestCase {
    func testRecordsCarryEveryModelField() {
        let item = BackupFixtures.cabinetItem(name: "Campari", brand: "Campari")
        let back = CabinetRecord(item).makeModel()
        XCTAssertEqual(back.id, item.id)
        XCTAssertEqual(back.ingredientStyleId, item.ingredientStyleId)
        XCTAssertEqual(back.ingredientFamilyId, item.ingredientFamilyId)
        XCTAssertEqual(back.categoryId, item.categoryId)
        XCTAssertEqual(back.displayName, "Campari")
        XCTAssertEqual(back.brand, "Campari")
        XCTAssertEqual(back.style, item.style)
        XCTAssertEqual(back.family, item.family)
        XCTAssertEqual(back.category, item.category)
        XCTAssertEqual(back.flavorProfile, BackupFixtures.flavor)
        XCTAssertEqual(back.dateAdded, item.dateAdded)

        let favourite = FavouriteRecipe(recipeId: UUID(), recipeName: "Negroni", dateFavourited: BackupFixtures.date(2))
        XCTAssertEqual(FavouriteRecord(FavouriteRecord(favourite).makeModel()), FavouriteRecord(favourite))
        let shopping = ShoppingItem(ingredientStyleId: UUID(), styleName: "Vermouth", dateAdded: BackupFixtures.date(3))
        XCTAssertEqual(ShoppingRecord(ShoppingRecord(shopping).makeModel()), ShoppingRecord(shopping))
        let take = RecipeTake(recipeId: UUID(), recipeName: "Negroni", rating: 3, notes: "Hm.", updatedAt: BackupFixtures.date(4))
        XCTAssertEqual(TakeRecord(TakeRecord(take).makeModel()), TakeRecord(take))
    }

    func testManifestSurvivesJSONIncludingMilliseconds() throws {
        let precise = Date(timeIntervalSince1970: 1_760_000_000.5)
        let manifest = BackupManifest(
            appVersion: "1.0", createdAt: precise,
            cabinet: [CabinetRecord(BackupFixtures.cabinetItem())],
            favourites: [FavouriteRecord(id: UUID(), recipeId: UUID(), recipeName: "Negroni", dateFavourited: BackupFixtures.date(1))],
            shopping: [ShoppingRecord(id: UUID(), ingredientStyleId: UUID(), styleName: "Gin", dateAdded: BackupFixtures.date(2))],
            takes: [TakeRecord(id: UUID(), recipeId: UUID(), recipeName: "Negroni", rating: 5, notes: "Yes", updatedAt: BackupFixtures.date(3))],
            photos: [PhotoRecord(id: UUID(), recipeId: UUID(), dateAdded: BackupFixtures.date(4), fullFile: "photos/a.jpg", thumbnailFile: "photos/a-thumb.jpg")])

        let data = try BackupJSON.encoder().encode(manifest)
        let decoded = try BackupJSON.decoder().decode(BackupManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"formatVersion\" : 2"))
    }

    func testUnknownKeysAreIgnored() throws {
        var object = try JSONSerialization.jsonObject(with: BackupFixtures.encoded(BackupManifest(appVersion: "1.0", createdAt: BackupFixtures.date(0)))) as! [String: Any]
        object["somethingNew"] = ["a": 1]
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(try BackupJSON.decoder().decode(BackupManifest.self, from: data).appVersion, "1.0")
    }

    func testErrorsMapToWhatTheUserSees() {
        XCTAssertEqual(BackupError.from(BackupError.damaged, otherwise: .exportFailed), .damaged)
        XCTAssertEqual(BackupError.from(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), otherwise: .exportFailed), .outOfSpace)
        XCTAssertEqual(BackupError.from(CocoaError(.fileWriteOutOfSpace), otherwise: .exportFailed), .outOfSpace)
        let wrapped = NSError(domain: "x", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        XCTAssertEqual(BackupError.from(wrapped, otherwise: .restoreFailed), .outOfSpace)
        XCTAssertEqual(BackupError.from(CocoaError(.fileReadNoPermission), otherwise: .restoreFailed), .restoreFailed)
    }
}
