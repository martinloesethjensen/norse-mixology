import XCTest
@testable import NorseMixologyCore

final class IngredientSearchTests: XCTestCase {
    private func loadCategories() throws -> [IngredientCategory] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        return try IngredientTaxonomy.loadCategories(from: Data(contentsOf: url))
    }

    func testSearchGinSurfacesMultipleGinStyles() throws {
        let categories = try loadCategories()
        let results = IngredientSearch.search("gin", in: categories)
        let names = Set(results.map(\.name))
        XCTAssertTrue(names.contains("London Dry Gin"))
        XCTAssertTrue(names.contains("Contemporary Gin"))
        XCTAssertGreaterThanOrEqual(results.count, 5)
    }

    func testSearchMatchesBrandName() throws {
        let categories = try loadCategories()
        let results = IngredientSearch.search("Tanqueray", in: categories)
        XCTAssertTrue(results.contains { $0.name == "London Dry Gin" })
    }

    func testSearchIsCaseInsensitive() throws {
        let categories = try loadCategories()
        XCTAssertEqual(
            IngredientSearch.search("GIN", in: categories).count,
            IngredientSearch.search("gin", in: categories).count
        )
    }

    func testEmptyQueryReturnsNoResults() throws {
        let categories = try loadCategories()
        XCTAssertTrue(IngredientSearch.search("   ", in: categories).isEmpty)
    }
}
