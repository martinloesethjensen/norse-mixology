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

    func testLoadFromCatalogPopulatesTaxonomyAndRecipes() throws {
        let categories = try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData())
        let recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
        let store = TaxonomyStore()
        store.load(categories: categories, recipes: recipes)

        XCTAssertTrue(store.isLoaded)
        XCTAssertTrue(store.recipesLoaded)
        XCTAssertFalse(store.isUnavailable)
        XCTAssertEqual(store.recipes, recipes)
        XCTAssertEqual(store.styleCount, IngredientTaxonomy.flattenStyles(categories).count)
        let ginStyle = try XCTUnwrap(store.stylesById.values.first { $0.name == "London Dry Gin" })
        XCTAssertEqual(store.familyNamesById[ginStyle.familyId], "Gin")
        XCTAssertEqual(store.categoryNamesById[ginStyle.categoryId], "Spirit")
    }

    func testMarkUnavailable() {
        let store = TaxonomyStore()
        store.markUnavailable()
        XCTAssertTrue(store.isUnavailable)
        XCTAssertFalse(store.isLoaded)
    }

    // A second, losing bootstrap must not overlay a catalog that is already showing.
    func testMarkUnavailableIsIgnoredOnceLoaded() throws {
        let store = TaxonomyStore()
        store.load(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()), recipes: [])
        store.markUnavailable()
        XCTAssertFalse(store.isUnavailable)
        XCTAssertTrue(store.isLoaded)
    }

    func testLoadClearsAnEarlierUnavailable() throws {
        let store = TaxonomyStore()
        store.markUnavailable()
        store.load(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()), recipes: [])
        XCTAssertFalse(store.isUnavailable)
        XCTAssertTrue(store.isLoaded)
    }
}
