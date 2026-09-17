import XCTest
@testable import NorseMixologyCore

final class TaxonomyStoreTests: XCTestCase {
    private func loadTaxonomyData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testLoadPopulatesCachesAndNameLookups() throws {
        let store = TaxonomyStore()
        store.load(taxonomyData: try loadTaxonomyData())

        XCTAssertTrue(store.isLoaded)
        XCTAssertGreaterThanOrEqual(store.styleCount, 60)
        XCTAssertGreaterThanOrEqual(store.categoryNamesById.count, 1)
        XCTAssertGreaterThanOrEqual(store.familyNamesById.count, 1)

        let ginStyle = try XCTUnwrap(store.stylesById.values.first { $0.name == "London Dry Gin" })
        XCTAssertEqual(store.familyNamesById[ginStyle.familyId], "Gin")
        XCTAssertEqual(store.categoryNamesById[ginStyle.categoryId], "Spirit")
    }

    func testLoadIsIdempotent() throws {
        let store = TaxonomyStore()
        let data = try loadTaxonomyData()
        store.load(taxonomyData: data)
        let firstCount = store.styleCount
        store.load(taxonomyData: data)
        XCTAssertEqual(store.styleCount, firstCount)
    }
}
