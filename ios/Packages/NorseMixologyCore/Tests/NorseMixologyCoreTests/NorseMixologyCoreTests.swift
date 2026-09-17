import XCTest
@testable import NorseMixologyCore

final class NorseMixologyCoreTests: XCTestCase {
    private func loadTaxonomyData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func loadRecipesData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "recipes", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // MARK: - Model round-trip

    func testFlavorProfileRoundTrip() throws {
        let profile = FlavorProfile(
            sweetness: 0.1, bitterness: 0.2, smokiness: 0.3, citrus: 0.4, floral: 0.5,
            spice: 0.6, herbal: 0.7, fruity: 0.8, oaky: 0.9, abv: 40.0
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(FlavorProfile.self, from: data)
        XCTAssertEqual(profile, decoded)
    }

    func testIngredientStyleRoundTrip() throws {
        let style = IngredientStyle(
            id: UUID(), name: "London Dry Gin", familyId: UUID(), categoryId: UUID(),
            exampleBrands: ["Tanqueray"],
            flavorProfile: FlavorProfile(sweetness: 0.1, bitterness: 0.2, smokiness: 0, citrus: 0.3, floral: 0.2, spice: 0.1, herbal: 0.7, fruity: 0.1, oaky: 0, abv: 40),
            abvMin: 37.5, abvMax: 47.0
        )
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(IngredientStyle.self, from: data)
        XCTAssertEqual(style, decoded)
    }

    func testRecipeRoundTrip() throws {
        let recipe = Recipe(
            id: UUID(), name: "Martini", description: "Dry and spirit-forward.",
            glassType: .martini, method: .stir,
            ingredients: [RecipeIngredient(ingredientStyleId: UUID(), amount: "60ml", preparation: nil, isOptional: false, substituteNotes: nil)],
            steps: ["Stir with ice.", "Strain into a chilled glass."],
            flavorProfile: FlavorProfile(sweetness: 0.1, bitterness: 0.2, smokiness: 0, citrus: 0.3, floral: 0.2, spice: 0.1, herbal: 0.7, fruity: 0.1, oaky: 0, abv: 40),
            tags: ["classic"], difficulty: .medium, imageURL: nil
        )
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertEqual(recipe, decoded)
    }

    // MARK: - Bundled data

    func testTaxonomyParsesWithAtLeast60Styles() throws {
        let categories = try IngredientTaxonomy.loadCategories(from: loadTaxonomyData())
        let styleCount = categories.reduce(0) { $0 + $1.families.reduce(0) { $0 + $1.styles.count } }
        XCTAssertGreaterThanOrEqual(styleCount, 60)
    }

    func testRecipesParseWithAtLeast150Recipes() throws {
        let recipes = try IngredientTaxonomy.loadRecipes(from: loadRecipesData())
        XCTAssertGreaterThanOrEqual(recipes.count, 150)
    }

    func testAllFlavorProfilesAreNonNegativeAndInRange() throws {
        let categories = try IngredientTaxonomy.loadCategories(from: loadTaxonomyData())
        for category in categories {
            for family in category.families {
                for style in family.styles {
                    let p = style.flavorProfile
                    for value in [p.sweetness, p.bitterness, p.smokiness, p.citrus, p.floral, p.spice, p.herbal, p.fruity, p.oaky] {
                        XCTAssertGreaterThanOrEqual(value, 0.0)
                        XCTAssertLessThanOrEqual(value, 1.0)
                    }
                }
            }
        }
    }

    func testEveryRecipeIngredientResolvesAgainstTaxonomy() throws {
        let categories = try IngredientTaxonomy.loadCategories(from: loadTaxonomyData())
        let styleIds = Set(IngredientTaxonomy.flattenStyles(categories).keys)
        let recipes = try IngredientTaxonomy.loadRecipes(from: loadRecipesData())

        for recipe in recipes {
            for ingredient in recipe.ingredients {
                XCTAssertTrue(
                    styleIds.contains(ingredient.ingredientStyleId),
                    "\(recipe.name) references unknown ingredientStyleId \(ingredient.ingredientStyleId)"
                )
            }
        }
    }
}
