import XCTest
@testable import NorseMixologyCore

/// Spec row 16: a catalog update removed a style that is still in the user's cabinet.
final class CatalogToleranceTests: XCTestCase {
    private var index: TaxonomyIndex!
    private var recipes: [Recipe]!

    override func setUpWithError() throws {
        index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
    }

    private func style(_ name: String) throws -> IngredientStyle {
        try XCTUnwrap(index.stylesById.values.first { $0.name == name })
    }

    private func item(for style: IngredientStyle) -> CabinetItem {
        CabinetItem(ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                    displayName: style.name, brand: nil, style: style.name,
                    family: index.familyName(for: style), category: index.categoryName(for: style),
                    flavorProfile: style.flavorProfile)
    }

    /// A cabinet snapshot of a gin style that no longer exists in the catalog,
    /// with a flavour profile identical to London Dry Gin.
    private func ghostGin() throws -> CabinetItem {
        let londonDry = try style("London Dry Gin")
        return CabinetItem(ingredientStyleId: UUID(), ingredientFamilyId: londonDry.familyId, categoryId: londonDry.categoryId,
                           displayName: "Discontinued Gin", brand: nil, style: "Discontinued Gin",
                           family: "Gin", category: "Spirit", flavorProfile: londonDry.flavorProfile)
    }

    private func summary(_ results: [RecipeMatchResult]) -> [String] {
        results.map { "\($0.recipe.name) \($0.matchType) \($0.matchScore)" }
    }

    func testGhostCabinetItemDoesNotChangeResults() throws {
        let vermouth = item(for: try style("Dry Vermouth"))
        let without = MatchingService.match(cabinet: [vermouth], recipes: recipes, index: index)
        let with = MatchingService.match(cabinet: [vermouth, try ghostGin()], recipes: recipes, index: index)
        XCTAssertEqual(summary(with), summary(without))
    }

    func testAcceptOverrideToAGhostStyleIsIgnored() throws {
        let londonDry = try style("London Dry Gin")
        let vermouth = item(for: try style("Dry Vermouth"))
        let ghost = try ghostGin()
        var prefs = MatchPreferences.default
        prefs.acceptOverrides[londonDry.id] = ghost.ingredientStyleId
        let without = MatchingService.match(cabinet: [vermouth], recipes: recipes, index: index, prefs: prefs)
        let with = MatchingService.match(cabinet: [vermouth, ghost], recipes: recipes, index: index, prefs: prefs)
        XCTAssertEqual(summary(with), summary(without))
    }

    func testRecipeIngredientMissingFromTheIndexDoesNotCrash() throws {
        let gin = item(for: try style("London Dry Gin"))
        let orphanIndex = TaxonomyIndex(categories: [])
        XCTAssertNoThrow(MatchingService.match(cabinet: [gin], recipes: recipes, index: orphanIndex))
    }
}
