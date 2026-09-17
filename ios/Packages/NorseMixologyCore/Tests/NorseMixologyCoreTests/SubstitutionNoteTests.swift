import XCTest
@testable import NorseMixologyCore

final class SubstitutionNoteTests: XCTestCase {
    private func loadTaxonomy() throws -> [IngredientCategory] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        return try IngredientTaxonomy.loadCategories(from: Data(contentsOf: url))
    }

    private func style(named name: String, in categories: [IngredientCategory]) throws -> IngredientStyle {
        let index = TaxonomyIndex(categories: categories)
        return try XCTUnwrap(index.stylesById.values.first { $0.name == name })
    }

    func testBourbonToRyeNoteMentionsSpicier() throws {
        let categories = try loadTaxonomy()
        let bourbon = try style(named: "Bourbon", in: categories)
        let rye = try style(named: "Rye Whiskey", in: categories)

        let note = SubstitutionNote.generate(required: bourbon, substitute: rye)
        XCTAssertTrue(note.contains("spicier"), "Expected note to mention 'spicier', got: \(note)")
        XCTAssertTrue(note.contains("Rye Whiskey"))
        XCTAssertTrue(note.contains("Bourbon"))
    }

    func testLondonDryToContemporaryNoteMentionsFloral() throws {
        let categories = try loadTaxonomy()
        let londonDry = try style(named: "London Dry Gin", in: categories)
        let contemporary = try style(named: "Contemporary Gin", in: categories)

        let note = SubstitutionNote.generate(required: londonDry, substitute: contemporary)
        XCTAssertTrue(note.contains("floral"), "Expected note to mention 'floral', got: \(note)")
    }

    func testCloseMatchFallbackWhenNoSignificantDelta() {
        let profile = FlavorProfile(sweetness: 0.3, bitterness: 0.1, smokiness: 0, citrus: 0.2, floral: 0.1, spice: 0.1, herbal: 0.2, fruity: 0.1, oaky: 0, abv: 40)
        let required = IngredientStyle(id: UUID(), name: "Style A", familyId: UUID(), categoryId: UUID(), exampleBrands: [], flavorProfile: profile, abvMin: 40, abvMax: 40)
        let substitute = IngredientStyle(id: UUID(), name: "Style B", familyId: UUID(), categoryId: UUID(), exampleBrands: [], flavorProfile: profile, abvMin: 40, abvMax: 40)

        let note = SubstitutionNote.generate(required: required, substitute: substitute)
        XCTAssertTrue(note.contains("close match"))
    }

    func testRatioHintOnlyAppliesToSweetenerSourRole() {
        let sweeter = FlavorProfile(sweetness: 0.9, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)
        let lessSweet = FlavorProfile(sweetness: 0.2, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)
        let required = IngredientStyle(id: UUID(), name: "Simple Syrup", familyId: UUID(), categoryId: UUID(), exampleBrands: [], flavorProfile: lessSweet, abvMin: 0, abvMax: 0)
        let substitute = IngredientStyle(id: UUID(), name: "Grenadine", familyId: UUID(), categoryId: UUID(), exampleBrands: [], flavorProfile: sweeter, abvMin: 0, abvMax: 0)

        XCTAssertNotNil(SubstitutionNote.ratioHint(role: .sweetenerSour, required: required, substitute: substitute))
        XCTAssertNil(SubstitutionNote.ratioHint(role: .base, required: required, substitute: substitute))
    }
}
