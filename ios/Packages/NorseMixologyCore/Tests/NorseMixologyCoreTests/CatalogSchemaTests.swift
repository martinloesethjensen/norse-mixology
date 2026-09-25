import XCTest
import GRDB
@testable import NorseMixologyCore

final class CatalogSchemaTests: XCTestCase {
    private func makeDatabase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { try CatalogSchema.create(in: $0) }
        return queue
    }

    private let categoryId = UUID().uuidString
    private let familyId = UUID().uuidString

    private func insertCategoryAndFamily(_ db: Database) throws {
        try db.execute(sql: "INSERT INTO category (id, name, sort_order) VALUES (?, 'Spirit', 0)", arguments: [categoryId])
        try db.execute(sql: "INSERT INTO family (id, category_id, name, sort_order) VALUES (?, ?, 'Gin', 0)", arguments: [familyId, categoryId])
    }

    private func insertStyle(_ db: Database, citrus: Double = 0.3, familyId overrideFamily: String? = nil) throws {
        var args: [(any DatabaseValueConvertible)?] = [UUID().uuidString, overrideFamily ?? familyId, categoryId, "London Dry Gin", 0, 37.5, 47.0]
        let profile = FlavorProfile(sweetness: 0.1, bitterness: 0.2, smokiness: 0, citrus: citrus, floral: 0.2, spice: 0.1, herbal: 0.7, fruity: 0.1, oaky: 0, abv: 42)
        args.append(contentsOf: CatalogSchema.profileValues(profile).map { $0 as (any DatabaseValueConvertible)? })
        let columns = (["id", "family_id", "category_id", "name", "sort_order", "abv_min", "abv_max"] + CatalogSchema.profileColumns)
        try db.execute(
            sql: "INSERT INTO style (\(columns.joined(separator: ", "))) VALUES (\(Array(repeating: "?", count: columns.count).joined(separator: ", ")))",
            arguments: StatementArguments(args)
        )
    }

    func testCreateSetsUserVersion() throws {
        let queue = try makeDatabase()
        let version = try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }
        XCTAssertEqual(version, CatalogSchema.version)
    }

    func testCreateMakesEveryTable() throws {
        let queue = try makeDatabase()
        let tables = try queue.read { try String.fetchSet($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        XCTAssertEqual(tables, ["catalog_meta", "category", "family", "style", "style_brand",
                                "recipe", "recipe_ingredient", "recipe_step", "recipe_tag"])
    }

    func testValidStyleInserts() throws {
        let queue = try makeDatabase()
        try queue.write { db in
            try insertCategoryAndFamily(db)
            try insertStyle(db)
        }
    }

    func testFlavourOutsideZeroToOneIsRejected() throws {
        let queue = try makeDatabase()
        XCTAssertThrowsError(try queue.write { db in
            try insertCategoryAndFamily(db)
            try insertStyle(db, citrus: 1.5)
        })
    }

    func testDanglingForeignKeyIsRejected() throws {
        let queue = try makeDatabase()
        XCTAssertThrowsError(try queue.write { db in
            try insertCategoryAndFamily(db)
            try insertStyle(db, familyId: UUID().uuidString)
        })
    }

    func testStrictTablesRejectWrongTypes() throws {
        let queue = try makeDatabase()
        XCTAssertThrowsError(try queue.write { db in
            try db.execute(sql: "INSERT INTO category (id, name, sort_order) VALUES ('x', 'Spirit', 'first')")
        })
    }
}
