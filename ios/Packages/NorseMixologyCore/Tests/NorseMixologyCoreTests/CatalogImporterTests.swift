import XCTest
import GRDB
@testable import NorseMixologyCore

final class CatalogImporterTests: XCTestCase {
    private var paths: CatalogPaths!

    override func setUpWithError() throws {
        paths = try CatalogFixtures.tempPaths()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.directory)
    }

    private func build(taxonomy: Data? = nil, recipes: Data? = nil, manifestFor: (taxonomy: Data, recipes: Data)? = nil) throws {
        let taxonomy = try taxonomy ?? CatalogFixtures.taxonomyData()
        let recipes = try recipes ?? CatalogFixtures.recipesData()
        let hashed = manifestFor ?? (taxonomy, recipes)
        try CatalogImporter.build(
            at: paths.staging,
            manifest: CatalogFixtures.manifest(taxonomy: hashed.taxonomy, recipes: hashed.recipes),
            taxonomyData: taxonomy,
            recipesData: recipes,
            source: .bundled,
            etag: nil
        )
    }

    private func assertNoStagingFile(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path), "failed import left a file", file: file, line: line)
    }

    func testBuildsADatabaseWithEveryRowAndMeta() throws {
        try build()
        let queue = try DatabaseQueue(path: paths.staging.path)
        defer { try? queue.close() }
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), CatalogSchema.version)
            XCTAssertGreaterThanOrEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM style") ?? 0, 60)
            XCTAssertGreaterThanOrEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recipe") ?? 0, 150)
            let meta = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT key, value FROM catalog_meta")
                .map { ($0["key"] as String, $0["value"] as String) })
            XCTAssertEqual(meta["contentVersion"], "aaaaaaaa")
            XCTAssertEqual(meta["source"], "bundled")
            XCTAssertEqual(meta["generatedAt"], CatalogDate.format(CatalogFixtures.t0))
            XCTAssertNil(meta["etag"])
        }
    }

    func testReplacesAnExistingFileAtTheDestination() throws {
        try Data("garbage".utf8).write(to: paths.staging)
        try build()
        let queue = try DatabaseQueue(path: paths.staging.path)
        defer { try? queue.close() }
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }, CatalogSchema.version)
    }

    func testHashMismatchIsRejected() throws {
        let taxonomy = try CatalogFixtures.taxonomyData()
        let recipes = try CatalogFixtures.recipesData()
        XCTAssertThrowsError(try build(taxonomy: taxonomy + Data(" ".utf8), recipes: recipes, manifestFor: (taxonomy, recipes))) { error in
            XCTAssertEqual(error as? CatalogError, .hashMismatch("taxonomy"))
        }
        assertNoStagingFile()
    }

    func testAnySkippedRecipeRejectsTheWholeCatalog() throws {
        let recipes = try CatalogFixtures.recipesData { $0[0]["glassType"] = "bucket" }
        XCTAssertThrowsError(try build(recipes: recipes)) { error in
            guard case CatalogError.malformedRecipes = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testTaxonomyThatIsNotJSONIsRejected() throws {
        XCTAssertThrowsError(try build(taxonomy: Data("<html>".utf8))) { error in
            guard case CatalogError.malformedTaxonomy = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testFamilyNestedUnderTheWrongCategoryIsRejected() throws {
        let taxonomy = try CatalogFixtures.taxonomyData { categories in
            var families = categories[0]["families"] as! [[String: Any]]
            families[0]["categoryId"] = UUID().uuidString
            categories[0]["families"] = families
        }
        XCTAssertThrowsError(try build(taxonomy: taxonomy)) { error in
            guard case CatalogError.invalidStructure = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testFlavourOutOfRangeIsAConstraintViolation() throws {
        let recipes = try CatalogFixtures.recipesData { recipes in
            var profile = recipes[0]["flavorProfile"] as! [String: Any]
            profile["citrus"] = 1.5
            recipes[0]["flavorProfile"] = profile
        }
        XCTAssertThrowsError(try build(recipes: recipes)) { error in
            guard case CatalogError.constraintViolation = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testDanglingStyleReferenceIsAConstraintViolation() throws {
        let recipes = try CatalogFixtures.recipesData { recipes in
            var ingredients = recipes[0]["ingredients"] as! [[String: Any]]
            ingredients[0]["ingredientStyleId"] = UUID().uuidString
            recipes[0]["ingredients"] = ingredients
        }
        XCTAssertThrowsError(try build(recipes: recipes)) { error in
            guard case CatalogError.constraintViolation = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testPromoteMovesStagingToLiveAndReplacesAnExistingLive() throws {
        try build()
        try paths.promoteStaging()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.live.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path))
        try build()
        try paths.promoteStaging()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path))
    }

    func testRemoveStagingDeletesLeftovers() throws {
        try Data("partial".utf8).write(to: paths.staging)
        try Data("journal".utf8).write(to: URL(fileURLWithPath: paths.staging.path + "-journal"))
        paths.removeStaging()
        assertNoStagingFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path + "-journal"))
    }
}
