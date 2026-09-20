import XCTest
@testable import NorseMixologyCore

/// Phase 6 (MVP Polish) hardening: tolerant catalog parsing, accessibility
/// descriptions, and the on-device matching performance budget.
final class HardeningTests: XCTestCase {
    private func bundledData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // MARK: - Tolerant recipe parsing

    func testMalformedRecipeEntryIsSkippedInsteadOfFailingTheWholeCatalog() throws {
        let original = try IngredientTaxonomy.loadRecipes(from: bundledData("recipes"))

        // Corrupt exactly one entry: an unknown glass type can't decode.
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: bundledData("recipes")) as? [[String: Any]])
        objects[1]["glassType"] = "not-a-real-glass"
        let corrupted = try JSONSerialization.data(withJSONObject: objects)

        let result = try IngredientTaxonomy.loadRecipesReportingSkipped(from: corrupted)

        XCTAssertEqual(result.recipes.count, original.count - 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertFalse(result.recipes.contains { $0.id == original[1].id })
        XCTAssertEqual(result.recipes.first?.id, original[0].id, "valid entries keep their order")
    }

    func testCleanCatalogReportsNothingSkipped() throws {
        let result = try IngredientTaxonomy.loadRecipesReportingSkipped(from: bundledData("recipes"))

        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertFalse(result.recipes.isEmpty)
    }

    func testLoadRecipesStillThrowsWhenTheFileIsNotAnArrayAtAll() {
        XCTAssertThrowsError(try IngredientTaxonomy.loadRecipes(from: Data("{\"oops\": true}".utf8)))
    }

    func testStoreLoadsTheValidRecipesEvenWhenOneEntryIsMalformed() throws {
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: bundledData("recipes")) as? [[String: Any]])
        let total = objects.count
        objects[0].removeValue(forKey: "name")
        let corrupted = try JSONSerialization.data(withJSONObject: objects)

        let store = TaxonomyStore()
        store.loadRecipes(from: corrupted)

        XCTAssertTrue(store.recipesLoaded)
        XCTAssertEqual(store.recipes.count, total - 1)
    }

    // MARK: - Flavour accessibility description

    private func profile(sweet: Double, bitter: Double, smoky: Double, citrus: Double, herbal: Double) -> FlavorProfile {
        FlavorProfile(sweetness: sweet, bitterness: bitter, smokiness: smoky, citrus: citrus, floral: 0, spice: 0, herbal: herbal, fruity: 0, oaky: 0, abv: 40)
    }

    func testAccessibilitySummaryDescribesEachDisplayedDimensionAsLowMediumOrHigh() {
        let summary = profile(sweet: 0.8, bitter: 0.1, smoky: 0.0, citrus: 0.5, herbal: 0.9).accessibilitySummary

        XCTAssertEqual(summary, "Sweetness: high, Bitterness: low, Smokiness: low, Citrus: medium, Herbal: high")
    }

    func testFlavourLevelBoundaries() {
        XCTAssertEqual(FlavorLevel(value: 0.0), .low)
        XCTAssertEqual(FlavorLevel(value: 0.33), .low)
        XCTAssertEqual(FlavorLevel(value: 0.34), .medium)
        XCTAssertEqual(FlavorLevel(value: 0.66), .medium)
        XCTAssertEqual(FlavorLevel(value: 0.67), .high)
        XCTAssertEqual(FlavorLevel(value: 1.0), .high)
    }

    // MARK: - Performance budget

    func testMatchingA30ItemCabinetAgainstTheFullCatalogIsWellUnder100ms() throws {
        let categories = try IngredientTaxonomy.loadCategories(from: bundledData("taxonomy"))
        let recipes = try IngredientTaxonomy.loadRecipes(from: bundledData("recipes"))
        let index = TaxonomyIndex(categories: categories)

        let cabinet = index.stylesById.values.sorted { $0.name < $1.name }.prefix(30).map { style in
            CabinetItem(
                ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                displayName: style.name, brand: nil, style: style.name,
                family: index.familyName(for: style), category: index.categoryName(for: style),
                flavorProfile: style.flavorProfile
            )
        }
        XCTAssertEqual(cabinet.count, 30)

        let start = CFAbsoluteTimeGetCurrent()
        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertGreaterThan(recipes.count, 100, "budget is defined against a realistically sized catalog")
        XCTAssertLessThan(elapsed, 0.1, "matched \(recipes.count) recipes in \(Int(elapsed * 1000))ms, \(results.count) results")
    }
}
