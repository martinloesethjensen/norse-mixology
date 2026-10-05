import XCTest
@testable import NorseMixologyCore

final class RecipeFilterTests: XCTestCase {
    private var index: TaxonomyIndex!
    private var recipes: [Recipe]!

    override func setUpWithError() throws {
        index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
    }

    private func names(_ filter: RecipeFilter) -> Set<String> {
        Set(recipes.filter { filter.matches($0, index: index) }.map(\.name))
    }

    private func filter(query: String = "", _ criteria: RecipeFilter.Criterion...) -> RecipeFilter {
        var filter = RecipeFilter()
        filter.query = query
        criteria.forEach { filter.toggle($0) }
        return filter
    }

    private func familyId(_ name: String) throws -> UUID {
        try XCTUnwrap(index.familyNamesById.first { $0.value == name }?.key, "no family \(name)")
    }

    // MARK: - Query

    func testEmptyAndWhitespaceQueriesMatchEverything() {
        XCTAssertEqual(names(filter()).count, recipes.count)
        XCTAssertEqual(names(filter(query: "  \n\t ")).count, recipes.count)
        XCTAssertTrue(filter(query: "   ").isEmpty)
    }

    func testQueryMatchesRecipeNameCaseInsensitively() {
        XCTAssertTrue(names(filter(query: "negroni")).contains("Negroni"))
    }

    func testQueryIgnoresDiacritics() {
        XCTAssertTrue(names(filter(query: "pina colada")).contains("Piña Colada"))
        XCTAssertTrue(names(filter(query: "vieux carre")).contains("Vieux Carré"))
    }

    func testQueryMatchesIngredientStyleAndFamilyNames() {
        XCTAssertTrue(names(filter(query: "chartreuse")).contains("Last Word"), "style name")
        XCTAssertTrue(names(filter(query: "curacao")).isSuperset(of: names(filter(query: "Orange Curaçao"))), "diacritics on style")
        let byFamily = names(filter(query: "vermouth"))
        XCTAssertTrue(byFamily.contains("Negroni"), "family name")
    }

    func testOddQueriesNeverCrashAndMatchNothing() {
        XCTAssertTrue(names(filter(query: "🍸🦄")).isEmpty)
        XCTAssertTrue(names(filter(query: String(repeating: "x", count: 1_000))).isEmpty)
        XCTAssertTrue(names(filter(query: "كوكتيل")).isEmpty)
    }

    // MARK: - Criteria

    func testStrengthComesFromAbvTags() throws {
        let noAbv = try XCTUnwrap(recipes.first { $0.tags.contains("no-abv") })
        let lowAbv = try XCTUnwrap(recipes.first { $0.tags.contains("low-abv") })
        let negroni = try XCTUnwrap(recipes.first { $0.name == "Negroni" })
        XCTAssertEqual(RecipeFilter.Strength(recipe: noAbv), .noABV)
        XCTAssertEqual(RecipeFilter.Strength(recipe: lowAbv), .lowABV)
        XCTAssertEqual(RecipeFilter.Strength(recipe: negroni), .regular)
        XCTAssertEqual(names(filter(.strength(.noABV))).count, recipes.filter { $0.tags.contains("no-abv") }.count)
    }

    func testBaseSpiritUsesTheBaseRoleFamily() throws {
        let gin = try familyId("Gin")
        let result = names(filter(.baseFamily(gin)))
        XCTAssertTrue(result.contains("Negroni"))
        XCTAssertFalse(result.contains("Daiquiri"))
        let negroni = try XCTUnwrap(recipes.first { $0.name == "Negroni" })
        XCTAssertEqual(RecipeFilter.baseFamilyIds(of: negroni, index: index), [gin])
    }

    func testValuesOfOneKindCombineWithOr() {
        let sour = names(filter(.tag("sour")))
        let tiki = names(filter(.tag("tiki")))
        XCTAssertEqual(names(filter(.tag("sour"), .tag("tiki"))), sour.union(tiki))
    }

    func testDifferentKindsCombineWithAnd() {
        let sour = names(filter(.tag("sour")))
        let shaken = names(filter(.method(.shake)))
        XCTAssertEqual(names(filter(.tag("sour"), .method(.shake))), sour.intersection(shaken))
    }

    func testQueryAndCriteriaCombineWithAnd() {
        let gin = names(filter(query: "gin"))
        let stirred = names(filter(.method(.stir)))
        XCTAssertEqual(names(filter(query: "gin", .method(.stir))), gin.intersection(stirred))
    }

    func testGlassAndDifficultyFilters() {
        XCTAssertEqual(names(filter(.glass(.coupe))), Set(recipes.filter { $0.glassType == .coupe }.map(\.name)))
        XCTAssertEqual(names(filter(.difficulty(.easy))), Set(recipes.filter { $0.difficulty == .easy }.map(\.name)))
    }

    // MARK: - Editing criteria

    func testToggleAddsThenRemovesAndKeepsInsertionOrder() {
        var filter = RecipeFilter()
        filter.toggle(.tag("sour"))
        filter.toggle(.method(.shake))
        XCTAssertEqual(filter.criteria, [.tag("sour"), .method(.shake)])
        filter.toggle(.tag("sour"))
        XCTAssertEqual(filter.criteria, [.method(.shake)])
        filter.remove(.method(.shake))
        XCTAssertTrue(filter.isEmpty)
    }

    func testClearResetsQueryAndCriteria() {
        var cleared = filter(query: "gin", .tag("sour"))
        cleared.clear()
        XCTAssertEqual(cleared, RecipeFilter())
    }

    // MARK: - Options and grouped results

    func testOptionsOnlyOfferValuesPresentInTheCatalog() {
        let options = RecipeFilterOptions(recipes: recipes, index: index)
        XCTAssertEqual(Set(options.methods), Set(recipes.map(\.method)))
        XCTAssertEqual(options.difficulties, [.easy, .medium, .advanced])
        XCTAssertTrue(options.tags.allSatisfy(RecipeFilter.styleTags.contains))
        XCTAssertTrue(options.baseFamilies.contains { $0.name == "Gin" })
        XCTAssertEqual(options.baseFamilies.map(\.name), options.baseFamilies.map(\.name).sorted())
    }

    func testFilteringGroupedResultsKeepsTiersAndOrder() throws {
        let gin = try XCTUnwrap(index.stylesById.values.first { $0.name == "London Dry Gin" })
        let cabinet = [gin].map { style in
            CabinetItem(ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                        displayName: style.name, brand: nil, style: style.name,
                        family: index.familyName(for: style), category: index.categoryName(for: style),
                        flavorProfile: style.flavorProfile)
        }
        let grouped = GroupedMatchResults(results: MatchingService.match(cabinet: cabinet, recipes: recipes, index: index))
        XCTAssertEqual(grouped.filtered(by: RecipeFilter(), index: index), grouped)
        let filtered = grouped.filtered(by: filter(.method(.stir)), index: index)
        XCTAssertEqual(filtered.perfect.map(\.id), grouped.perfect.filter { $0.recipe.method == .stir }.map(\.id))
        XCTAssertEqual(filtered.almost.map(\.id), grouped.almost.filter { $0.recipe.method == .stir }.map(\.id))
        XCTAssertEqual(filtered.exploring.map(\.id), grouped.exploring.filter { $0.recipe.method == .stir }.map(\.id))
    }
}
