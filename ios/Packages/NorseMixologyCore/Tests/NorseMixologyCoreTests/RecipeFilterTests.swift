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

    // MARK: - My ratings

    private func ratedNames(_ criteria: RecipeFilter.Criterion..., ratings: [UUID: Int]) -> Set<String> {
        var filter = RecipeFilter()
        criteria.forEach { filter.toggle($0) }
        return Set(recipes.filter { filter.matches($0, index: index, ratings: ratings) }.map(\.name))
    }

    private func ratings(_ pairs: (String, Int)...) throws -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (name, stars) in pairs {
            result[try XCTUnwrap(recipes.first { $0.name == name }, "no recipe named \(name)").id] = stars
        }
        return result
    }

    func testRatedKeepsOnlyRatedRecipes() throws {
        let mine = try ratings(("Negroni", 2), ("Daiquiri", 5))
        XCTAssertEqual(ratedNames(.myRating(.rated), ratings: mine), ["Negroni", "Daiquiri"])
    }

    func testFourStarsOrMoreKeepsOnlyHighRatings() throws {
        let mine = try ratings(("Negroni", 3), ("Daiquiri", 4), ("Margarita", 5))
        XCTAssertEqual(ratedNames(.myRating(.fourOrMore), ratings: mine), ["Daiquiri", "Margarita"])
    }

    func testRatingCriteriaFormOneOrGroupAndCombineWithOtherKindsByAnd() throws {
        let mine = try ratings(("Negroni", 1), ("Daiquiri", 5))
        // Both in the group: rated OR 4+ is just "rated".
        XCTAssertEqual(ratedNames(.myRating(.rated), .myRating(.fourOrMore), ratings: mine), ["Negroni", "Daiquiri"])
        // AND with another kind: only rated recipes that are also built (Negroni is built, Daiquiri is shaken).
        let stirredAndRated = ratedNames(.myRating(.rated), .method(.build), ratings: mine)
        XCTAssertTrue(stirredAndRated.isSubset(of: ["Negroni", "Daiquiri"]))
        XCTAssertEqual(stirredAndRated, Set(["Negroni", "Daiquiri"].filter { name in
            recipes.first { $0.name == name }?.method == .build
        }))
    }

    func testWithoutARatingsDictionaryNothingCountsAsRated() {
        XCTAssertTrue(names(filter(.myRating(.rated))).isEmpty)
        XCTAssertTrue(names(filter(.myRating(.fourOrMore))).isEmpty)
    }

    func testGroupedFilteringPassesTheRatingsThrough() throws {
        let mine = try ratings(("Negroni", 5), ("Aviation", 2))
        var rated = RecipeFilter()
        rated.toggle(.myRating(.rated))

        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)
        let availability = GroupedAvailability(entries: entries, profile: .neutral).filtered(by: rated, index: index, ratings: mine)
        XCTAssertEqual(Set(availability.allIds), Set(mine.keys))

        let matches = recipes.map { RecipeMatchResult(recipe: $0, matchScore: 1, matchType: .exact, substitutions: []) }
        let grouped = GroupedMatchResults(results: matches).filtered(by: rated, index: index, ratings: mine)
        XCTAssertEqual(Set(grouped.perfect.map(\.id)), Set(mine.keys))
    }

    func testRatingChipLabels() {
        XCTAssertEqual(RecipeFilter.MyRating.rated.displayName, "Rated")
        XCTAssertEqual(RecipeFilter.MyRating.fourOrMore.displayName, "4 stars or more")
    }
}
