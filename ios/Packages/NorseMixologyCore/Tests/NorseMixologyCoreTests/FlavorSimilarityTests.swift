import XCTest
@testable import NorseMixologyCore

final class FlavorSimilarityTests: XCTestCase {
    private func loadTaxonomy() throws -> [IngredientCategory] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        return try IngredientTaxonomy.loadCategories(from: Data(contentsOf: url))
    }

    private func style(named name: String, in categories: [IngredientCategory]) throws -> IngredientStyle {
        let index = TaxonomyIndex(categories: categories)
        return try XCTUnwrap(index.stylesById.values.first { $0.name == name })
    }

    func testIdenticalProfilesAreFullySimilar() {
        let profile = FlavorProfile(sweetness: 0.4, bitterness: 0.1, smokiness: 0.2, citrus: 0.3, floral: 0.1, spice: 0.2, herbal: 0.1, fruity: 0.3, oaky: 0.2, abv: 40)
        XCTAssertEqual(FlavorSimilarity.cosine(profile, profile), 1.0, accuracy: 0.0001)
    }

    func testOrthogonalProfilesAreNotSimilar() {
        let a = FlavorProfile(sweetness: 1.0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)
        let b = FlavorProfile(sweetness: 0, bitterness: 1.0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)
        XCTAssertEqual(FlavorSimilarity.cosine(a, b), 0.0, accuracy: 0.0001)
    }

    func testZeroVectorReturnsZero() {
        let zero = FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)
        let other = FlavorProfile(sweetness: 0.5, bitterness: 0.5, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 40)
        XCTAssertEqual(FlavorSimilarity.cosine(zero, other), 0.0)
    }

    func testAbvIsExcludedFromSimilarity() {
        let a = FlavorProfile(sweetness: 0.5, bitterness: 0.2, smokiness: 0, citrus: 0.1, floral: 0, spice: 0, herbal: 0, fruity: 0.2, oaky: 0, abv: 10)
        let b = FlavorProfile(sweetness: 0.5, bitterness: 0.2, smokiness: 0, citrus: 0.1, floral: 0, spice: 0, herbal: 0, fruity: 0.2, oaky: 0, abv: 90)
        XCTAssertEqual(FlavorSimilarity.cosine(a, b), 1.0, accuracy: 0.0001)
    }

    func testBourbonIsMoreSimilarToRyeThanToIslayScotch() throws {
        let categories = try loadTaxonomy()
        let bourbon = try style(named: "Bourbon", in: categories)
        let rye = try style(named: "Rye Whiskey", in: categories)
        let islay = try style(named: "Scotch Single Malt (Islay)", in: categories)

        let bourbonRye = FlavorSimilarity.cosine(bourbon.flavorProfile, rye.flavorProfile)
        let bourbonIslay = FlavorSimilarity.cosine(bourbon.flavorProfile, islay.flavorProfile)

        XCTAssertGreaterThan(bourbonRye, bourbonIslay, "Bourbon should read closer to Rye than to a heavily-peated Islay Scotch")
        XCTAssertGreaterThan(bourbonRye, 0.6)
        XCTAssertLessThan(bourbonIslay, 0.7)
    }
}
