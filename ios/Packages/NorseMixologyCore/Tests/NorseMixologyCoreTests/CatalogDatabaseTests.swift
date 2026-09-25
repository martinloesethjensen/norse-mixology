import XCTest
import GRDB
@testable import NorseMixologyCore

final class CatalogDatabaseTests: XCTestCase {
    private var paths: CatalogPaths!

    override func setUpWithError() throws {
        paths = try CatalogFixtures.tempPaths()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.directory)
    }

    private func buildLive(source: CatalogSource = .bundled, etag: String? = nil) throws {
        let taxonomy = try CatalogFixtures.taxonomyData()
        let recipes = try CatalogFixtures.recipesData()
        let staging = paths.makeStaging()
        try CatalogImporter.build(at: staging, manifest: CatalogFixtures.manifest(taxonomy: taxonomy, recipes: recipes),
                                  taxonomyData: taxonomy, recipesData: recipes, source: source, etag: etag)
        try paths.promote(staging)
    }

    func testRoundTripEqualsTheJSONLoaders() throws {
        try buildLive()
        let loaded = try CatalogDatabase.load(from: paths.live)
        XCTAssertEqual(loaded.categories, try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        XCTAssertEqual(loaded.recipes, try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData()))
    }

    func testMetaRoundTrips() throws {
        try buildLive(source: .remote, etag: "\"abc\"")
        let meta = try CatalogDatabase.load(from: paths.live).meta
        XCTAssertEqual(meta, CatalogMeta(schemaVersion: 1, contentVersion: "aaaaaaaa", generatedAt: CatalogFixtures.t0, source: .remote, etag: "\"abc\""))
    }

    func testMissingFileThrowsMissingDatabase() {
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live)) { error in
            XCTAssertEqual(error as? CatalogError, .missingDatabase)
        }
    }

    func testWrongUserVersionThrowsSchemaMismatch() throws {
        try buildLive()
        let queue = try DatabaseQueue(path: paths.live.path)
        try queue.writeWithoutTransaction { try $0.execute(sql: "PRAGMA user_version = 0") }
        try queue.close()
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live)) { error in
            XCTAssertEqual(error as? CatalogError, .schemaMismatch(found: 0))
        }
    }

    func testGarbageFileThrowsCorruptDatabase() throws {
        try Data(repeating: 0x42, count: 4096).write(to: paths.live)
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live)) { error in
            guard case CatalogError.corruptDatabase = error else { return XCTFail("got \(error)") }
        }
    }

    func testTruncatedFileThrowsInsteadOfCrashing() throws {
        try buildLive()
        let handle = try FileHandle(forWritingTo: paths.live)
        try handle.truncate(atOffset: 8192)
        try handle.close()
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live))
    }

    func testLoadingDoesNotModifyTheFile() throws {
        try buildLive()
        let before = try Data(contentsOf: paths.live)
        _ = try CatalogDatabase.load(from: paths.live)
        XCTAssertEqual(try Data(contentsOf: paths.live), before)
    }
}
