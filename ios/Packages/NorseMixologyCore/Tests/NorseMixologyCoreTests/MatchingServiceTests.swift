import XCTest
@testable import NorseMixologyCore

final class MatchingServiceTests: XCTestCase {
    private func loadTaxonomy() throws -> [IngredientCategory] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        return try IngredientTaxonomy.loadCategories(from: Data(contentsOf: url))
    }

    private func loadRecipes() throws -> [Recipe] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "recipes", withExtension: "json"))
        return try IngredientTaxonomy.loadRecipes(from: Data(contentsOf: url))
    }

    private func style(named name: String, in index: TaxonomyIndex) throws -> IngredientStyle {
        try XCTUnwrap(index.stylesById.values.first { $0.name == name })
    }

    private func cabinetItem(for style: IngredientStyle, index: TaxonomyIndex) -> CabinetItem {
        CabinetItem(
            ingredientStyleId: style.id,
            ingredientFamilyId: style.familyId,
            categoryId: style.categoryId,
            displayName: style.name,
            brand: nil,
            style: style.name,
            family: index.familyName(for: style),
            category: index.categoryName(for: style),
            flavorProfile: style.flavorProfile
        )
    }

    func testExactNegroniCabinetScoresOne() throws {
        let categories = try loadTaxonomy()
        let recipes = try loadRecipes()
        let index = TaxonomyIndex(categories: categories)

        let cabinet = try [
            style(named: "London Dry Gin", in: index),
            style(named: "Bitter Aperitif", in: index),
            style(named: "Sweet/Rosso Vermouth", in: index),
        ].map { cabinetItem(for: $0, index: index) }

        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index)
        let negroni = try XCTUnwrap(results.first { $0.recipe.name == "Negroni" })

        XCTAssertEqual(negroni.matchType, .exact)
        XCTAssertEqual(negroni.matchScore, 1.0, accuracy: 0.0001)
        XCTAssertEqual(results.first?.recipe.name, "Negroni", "Negroni should be the top result")
    }

    func testBourbonReplacedByRyeMakesOldFashionedPartial() throws {
        let categories = try loadTaxonomy()
        let recipes = try loadRecipes()
        let index = TaxonomyIndex(categories: categories)

        let cabinet = try [
            style(named: "Rye Whiskey", in: index), // recipe calls for Bourbon
            style(named: "Demerara Syrup", in: index),
            style(named: "Angostura Bitters", in: index),
        ].map { cabinetItem(for: $0, index: index) }

        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index, prefs: .default)
        let oldFashioned = try XCTUnwrap(results.first { $0.recipe.name == "Old Fashioned" })

        XCTAssertEqual(oldFashioned.matchType, .partial)
        XCTAssertLessThan(oldFashioned.matchScore, 1.0)
        let sub = try XCTUnwrap(oldFashioned.substitutions.first { $0.required.name == "Bourbon" })
        XCTAssertEqual(sub.substitute.name, "Rye Whiskey")
        XCTAssertFalse(sub.note.isEmpty)
    }

    func testEmptyCabinetReturnsEmptyResults() throws {
        let categories = try loadTaxonomy()
        let recipes = try loadRecipes()
        let results = MatchingService.match(cabinet: [], recipes: recipes, index: TaxonomyIndex(categories: categories))
        XCTAssertTrue(results.isEmpty)
    }

    func testCabinetWithNoUsefulIngredientsReturnsNoResults() throws {
        let categories = try loadTaxonomy()
        let recipes = try loadRecipes()
        let index = TaxonomyIndex(categories: categories)

        // Only a garnish-role fresh herb — no recipe's base spirit can resolve from this alone.
        let cabinet = [cabinetItem(for: try style(named: "Fresh Basil", in: index), index: index)]
        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index)
        XCTAssertTrue(results.isEmpty)
    }

    func testGinReplacedByVodkaDropsNegroniEntirely() throws {
        let categories = try loadTaxonomy()
        let recipes = try loadRecipes()
        let index = TaxonomyIndex(categories: categories)

        let cabinet = try [
            style(named: "Neutral Vodka", in: index), // different family than Gin — no cosine fallback possible
            style(named: "Bitter Aperitif", in: index),
            style(named: "Sweet/Rosso Vermouth", in: index),
        ].map { cabinetItem(for: $0, index: index) }

        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index)
        XCTAssertFalse(results.contains { $0.recipe.name == "Negroni" })
    }

    func testStricterPreferencesSurfaceFewerOrEqualPartialMatches() throws {
        let categories = try loadTaxonomy()
        let recipes = try loadRecipes()
        let index = TaxonomyIndex(categories: categories)

        // A broad, imperfect cabinet likely to generate several borderline substitutions.
        let cabinet = try [
            "Rye Whiskey", "Contemporary Gin", "White/Blanco Rum", "Blanco Tequila",
            "Demerara Syrup", "Angostura Bitters", "Lime Juice", "Lemon Juice", "Simple Syrup",
        ].map { try cabinetItem(for: style(named: $0, in: index), index: index) }

        var adventurous = MatchPreferences.default
        adventurous.strictness = 0.0
        var strict = MatchPreferences.default
        strict.strictness = 1.0

        let adventurousResults = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index, prefs: adventurous)
        let strictResults = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index, prefs: strict)

        let adventurousPartials = adventurousResults.filter { $0.matchType == .partial }.count
        let strictPartials = strictResults.filter { $0.matchType == .partial }.count

        XCTAssertLessThanOrEqual(strictPartials, adventurousPartials)
        XCTAssertLessThan(strictPartials, adventurousPartials, "Expected strictness to meaningfully reduce partial matches for this cabinet")
    }

    func testResultsAreSortedExactFirstThenByScore() throws {
        let categories = try loadTaxonomy()
        let recipes = try loadRecipes()
        let index = TaxonomyIndex(categories: categories)

        let cabinet = try [
            style(named: "London Dry Gin", in: index),
            style(named: "Bitter Aperitif", in: index),
            style(named: "Sweet/Rosso Vermouth", in: index),
            style(named: "Rye Whiskey", in: index),
            style(named: "Demerara Syrup", in: index),
            style(named: "Angostura Bitters", in: index),
        ].map { cabinetItem(for: $0, index: index) }

        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index)

        var seenPartial = false
        var previousScore = 1.0
        for result in results {
            if result.matchType == .partial {
                seenPartial = true
                XCTAssertLessThanOrEqual(result.matchScore, previousScore)
                previousScore = result.matchScore
            } else {
                XCTAssertFalse(seenPartial, "All exact results must sort before any partial result")
            }
        }
    }

    // MARK: - Substitution rules

    private func results(_ names: String...) throws -> [RecipeMatchResult] {
        let index = TaxonomyIndex(categories: try loadTaxonomy())
        let cabinet = try names.map { cabinetItem(for: try style(named: $0, in: index), index: index) }
        return MatchingService.match(cabinet: cabinet, recipes: try loadRecipes(), index: index)
    }

    func testEveryRuleNamesARealCatalogStyle() throws {
        let names = Set(TaxonomyIndex(categories: try loadTaxonomy()).stylesById.values.map(\.name))
        for rule in CuratedSubstitutions.all {
            XCTAssertTrue(names.contains(rule.requiredStyleName), rule.requiredStyleName)
            XCTAssertTrue(names.contains(rule.substituteStyleName), rule.substituteStyleName)
        }
        let grouped = SubstitutionGroups.all.flatMap { $0 }
        for name in grouped { XCTAssertTrue(names.contains(name), name) }
        XCTAssertEqual(grouped.count, Set(grouped).count, "a style may belong to only one group")
    }

    func testFreshLimeStandsInForLimeJuice() throws {
        let daiquiri = try XCTUnwrap(try results("White/Blanco Rum", "Fresh Lime", "Simple Syrup").first { $0.recipe.name == "Daiquiri" })
        XCTAssertEqual(daiquiri.matchType, .exact)
        XCTAssertEqual(daiquiri.substitutions.map(\.substitute.name), ["Fresh Lime"])
    }

    func testOrangeJuiceDoesNotSourADaiquiri() throws {
        XCTAssertFalse(try results("White/Blanco Rum", "Orange Juice", "Simple Syrup").contains { $0.recipe.name == "Daiquiri" })
    }

    func testTomatoJuiceDoesNotStandInForPineapple() throws {
        XCTAssertFalse(try results("White/Blanco Rum", "Tomato Juice", "Coconut Cream").contains { $0.recipe.name == "Piña Colada" })
    }

    func testSweetVermouthDoesNotMakeAMartini() throws {
        XCTAssertFalse(try results("London Dry Gin", "Sweet/Rosso Vermouth").contains { $0.recipe.name == "Martini" })
    }

    func testCuratedRulesAreOneWay() throws {
        // Orgeat → Amaretto is allowed; a non-alcoholic syrup must not replace the Amaretto Sour's base.
        XCTAssertFalse(try results("Orgeat", "Lemon Juice", "Simple Syrup").contains { $0.recipe.name == "Amaretto Sour" })
    }

    func testGingerAleStillStandsInForGingerBeer() throws {
        let mule = try XCTUnwrap(try results("Neutral Vodka", "Lime Juice", "Ginger Ale").first { $0.recipe.name == "Moscow Mule" })
        XCTAssertEqual(mule.matchType, .partial)
        XCTAssertEqual(mule.substitutions.map(\.substitute.name), ["Ginger Ale"])
    }
}
