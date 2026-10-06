import XCTest
@testable import NorseMixologyCore

/// A recipe's flavour profile is a blend, so its scores run far below an
/// ingredient's: at the ingredient threshold of 0.5 only 44 of 158 recipes
/// show a note, and bitterness never gets there (the catalog maximum is 0.44).
/// Recipes are therefore scored against the most extreme recipe on each axis.
final class RecipeFlavorScaleTests: XCTestCase {
    private func profile(sweet: Double = 0, bitter: Double = 0, smoky: Double = 0, citrus: Double = 0, herbal: Double = 0,
                         floral: Double = 0.1, abv: Double = 20) -> FlavorProfile {
        FlavorProfile(sweetness: sweet, bitterness: bitter, smokiness: smoky, citrus: citrus,
                      floral: floral, spice: 0, herbal: herbal, fruity: 0, oaky: 0, abv: abv)
    }

    private func recipe(_ name: String, _ flavor: FlavorProfile) -> Recipe {
        Recipe(id: UUID(), name: name, description: "", glassType: .rocks, method: .stir, ingredients: [], steps: [],
               flavorProfile: flavor, tags: [], difficulty: .easy, imageURL: nil)
    }

    private func catalog() throws -> [Recipe] {
        try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
    }

    // MARK: - Scaling

    func testEachAxisIsDividedByItsCatalogMaximum() {
        let scale = RecipeFlavorScale(recipes: [
            recipe("A", profile(sweet: 0.4, bitter: 0.2, smoky: 0.3, citrus: 0.5, herbal: 0.6)),
            recipe("B", profile(sweet: 0.8, bitter: 0.4, smoky: 0.3, citrus: 0.25, herbal: 0.3)),
        ])
        let scaled = scale.relative(profile(sweet: 0.4, bitter: 0.2, smoky: 0.3, citrus: 0.25, herbal: 0.3))
        XCTAssertEqual(scaled.sweetness, 0.5, accuracy: 0.0001)
        XCTAssertEqual(scaled.bitterness, 0.5, accuracy: 0.0001)
        XCTAssertEqual(scaled.smokiness, 1.0, accuracy: 0.0001)
        XCTAssertEqual(scaled.citrus, 0.5, accuracy: 0.0001)
        XCTAssertEqual(scaled.herbal, 0.5, accuracy: 0.0001)
    }

    func testScaledScoresAreCappedAtOneAndOtherFieldsAreUntouched() {
        let scale = RecipeFlavorScale(recipes: [recipe("A", profile(sweet: 0.4))])
        let scaled = scale.relative(profile(sweet: 0.9, floral: 0.33, abv: 12))
        XCTAssertEqual(scaled.sweetness, 1.0)
        XCTAssertEqual(scaled.floral, 0.33)
        XCTAssertEqual(scaled.abv, 12)
    }

    func testTinyMaximaAreFlooredSoNoiseIsNotBlownUp() {
        // No recipe is smoky: a 0.05 smoke score must not read as a strong note.
        let scale = RecipeFlavorScale(recipes: [recipe("A", profile(sweet: 0.4, smoky: 0.01)), recipe("B", profile(sweet: 0.2))])
        XCTAssertEqual(scale.relative(profile(smoky: 0.05)).smokiness, 0.25, accuracy: 0.0001)
        XCTAssertEqual(RecipeFlavorScale(recipes: []).relative(profile(sweet: 0.1)).sweetness, 0.5, accuracy: 0.0001)
    }

    // MARK: - Real catalog

    func testKnownRecipesReadTheWayABartenderWouldExpect() throws {
        let recipes = try catalog()
        let scale = RecipeFlavorScale(recipes: recipes)
        func notes(_ name: String) throws -> [FlavorNote] {
            let found = try XCTUnwrap(recipes.first { $0.name == name }, "no recipe named \(name)")
            return FlavorNotes.notes(for: scale.relative(found.flavorProfile))
        }
        XCTAssertEqual(try notes("Negroni"), [FlavorNote(axis: .bitter, isStrong: true), FlavorNote(axis: .herbal, isStrong: true)])
        XCTAssertEqual(try notes("Margarita"), [FlavorNote(axis: .citrus, isStrong: true)])
        XCTAssertEqual(try notes("Old Fashioned"), [FlavorNote(axis: .sweet, isStrong: true)])
        XCTAssertEqual(try notes("Penicillin").first, FlavorNote(axis: .smoky, isStrong: true))
    }

    func testMostRecipesHaveANoteAndNoSingleNoteDominates() throws {
        let recipes = try catalog()
        let scale = RecipeFlavorScale(recipes: recipes)
        let noted = recipes.map { FlavorNotes.notes(for: scale.relative($0.flavorProfile)) }

        let neutral = noted.filter(\.isEmpty).count
        XCTAssertLessThan(Double(neutral) / Double(recipes.count), 0.35, "too many recipes read Neutral")
        XCTAssertGreaterThan(Double(neutral) / Double(recipes.count), 0.05, "Neutral should still exist")

        for axis in FlavorAxis.allCases {
            let count = noted.filter { $0.contains { $0.axis == axis } }.count
            XCTAssertLessThan(Double(count) / Double(recipes.count), 0.7, "\(axis) is on nearly every recipe")
        }
        // The same rule at the ingredient threshold would leave most recipes blank — the reason for the scale.
        let unscaledNeutral = recipes.filter { FlavorNotes.notes(for: $0.flavorProfile).isEmpty }.count
        XCTAssertGreaterThan(unscaledNeutral, neutral + 40)
    }
}
