import XCTest
@testable import NorseMixologyCore

/// Shopping List spec §2: ready-now, then moves-closer, then taste fit, then name.
final class BuyNextRankingTests: XCTestCase {
    private let zero = FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)

    private func style(_ name: String) -> IngredientStyle {
        IngredientStyle(id: UUID(), name: name, familyId: UUID(), categoryId: UUID(), exampleBrands: [],
                        flavorProfile: zero, abvMin: 0, abvMax: 0)
    }

    private func recipe(_ name: String, sweetness: Double = 0.5, bitterness: Double = 0.5) -> Recipe {
        Recipe(id: UUID(), name: name, description: "", glassType: .rocks, method: .stir, ingredients: [], steps: [],
               flavorProfile: FlavorProfile(sweetness: sweetness, bitterness: bitterness, smokiness: 0.5, citrus: 0.5,
                                            floral: 0, spice: 0, herbal: 0.5, fruity: 0, oaky: 0, abv: 20),
               tags: [], difficulty: .easy, imageURL: nil)
    }

    private func missing(_ recipe: Recipe, _ styles: IngredientStyle...) -> CatalogEntry {
        CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: styles)
    }

    private func ready(_ recipe: Recipe) -> CatalogEntry {
        CatalogEntry(recipe: recipe, match: RecipeMatchResult(recipe: recipe, matchScore: 1, matchType: .exact, substitutions: []),
                     substitutions: [], missing: [])
    }

    private func rank(_ entries: [CatalogEntry], listed: Set<UUID> = [], profile: UserTasteProfile = .neutral,
                      limit: Int = 5) -> [BuyNextSuggestion] {
        BuyNextRanking.rank(entries: entries, listedStyleIds: listed, profile: profile, limit: limit)
    }

    private let sweetTooth = UserTasteProfile(sweetness: 1, bitterness: 0, citrus: 0.5, smokiness: 0.5, herbal: 0.5,
                                              hasCompletedOnboarding: true)

    // MARK: - Counting

    func testReadyNowCountsRecipesWhoseOnlyMissingIngredientIsTheStyle() {
        let x = style("X"), y = style("Y")
        let result = rank([missing(recipe("A"), x), missing(recipe("B"), x), missing(recipe("C"), x, y)])

        XCTAssertEqual(result.map(\.style.name), ["X", "Y"])
        XCTAssertEqual(result[0].readyNow, 2)
        XCTAssertEqual(result[0].movesCloser, 1)
        XCTAssertEqual(result[0].readyNowRecipeNames, ["A", "B"])
        XCTAssertEqual(result[1].readyNow, 0)
        XCTAssertEqual(result[1].movesCloser, 1)
    }

    func testReadyEntriesContributeNothingAndNothingMissingIsEmpty() {
        XCTAssertTrue(rank([ready(recipe("A")), ready(recipe("B"))]).isEmpty)
        XCTAssertTrue(rank([]).isEmpty)
    }

    // MARK: - Ordering

    func testReadyNowBeatsMovesCloser() {
        let x = style("X"), y = style("Y"), z = style("Z")
        // X: 1 ready now. Y: 0 ready now but 3 closer.
        let result = rank([
            missing(recipe("A"), x),
            missing(recipe("B"), y, z), missing(recipe("C"), y, z), missing(recipe("D"), y, z),
        ])
        XCTAssertEqual(result.first?.style.name, "X")
    }

    func testMovesCloserBreaksReadyNowTies() {
        let x = style("X"), y = style("Y"), z = style("Z")
        let result = rank([
            missing(recipe("A"), x),
            missing(recipe("B"), y),
            missing(recipe("C"), y, z), missing(recipe("D"), y, z),
        ])
        XCTAssertEqual(Array(result.prefix(2)).map(\.style.name), ["Y", "X"])
    }

    func testEmptyCabinetStyleShapeRanksByMovesCloser() {
        let gin = style("Gin"), lime = style("Lime"), mint = style("Mint")
        // Every recipe needs two or more bottles, as with an empty cabinet.
        let result = rank([
            missing(recipe("A"), gin, lime), missing(recipe("B"), gin, lime), missing(recipe("C"), gin, mint),
        ])
        XCTAssertEqual(result.map(\.style.name), ["Gin", "Lime", "Mint"])
        XCTAssertTrue(result.allSatisfy { $0.readyNow == 0 })
        XCTAssertEqual(result.map(\.movesCloser), [3, 2, 1])
    }

    func testIdenticalScoresSortByName() {
        let b = style("Bravo"), a = style("Alpha"), c = style("Charlie")
        let result = rank([missing(recipe("R1"), b), missing(recipe("R2"), c), missing(recipe("R3"), a)])
        XCTAssertEqual(result.map(\.style.name), ["Alpha", "Bravo", "Charlie"])
    }

    func testActiveTasteProfileBreaksTiesButNeverOverridesCounts() {
        let bitterBottle = style("Aaa Bitter"), sweetBottle = style("Zzz Sweet"), popular = style("Popular")
        let result = rank([
            missing(recipe("Bitter one", sweetness: 0, bitterness: 1), bitterBottle),
            missing(recipe("Sweet one", sweetness: 1, bitterness: 0), sweetBottle),
            missing(recipe("Bitter two", sweetness: 0, bitterness: 1), popular),
            missing(recipe("Bitter three", sweetness: 0, bitterness: 1), popular),
        ], profile: sweetTooth)

        XCTAssertEqual(result.map(\.style.name), ["Popular", "Zzz Sweet", "Aaa Bitter"])
        // Neutral profile: the tie falls back to name.
        let neutral = rank([
            missing(recipe("Bitter one", sweetness: 0, bitterness: 1), bitterBottle),
            missing(recipe("Sweet one", sweetness: 1, bitterness: 0), sweetBottle),
        ])
        XCTAssertEqual(neutral.map(\.style.name), ["Aaa Bitter", "Zzz Sweet"])
    }

    func testReadyNowRecipeNamesAreBestTasteFitFirst() {
        let x = style("X")
        let entries = [
            missing(recipe("Bitter", sweetness: 0, bitterness: 1), x),
            missing(recipe("Sweet", sweetness: 1, bitterness: 0), x),
        ]
        XCTAssertEqual(rank(entries, profile: sweetTooth).first?.readyNowRecipeNames, ["Sweet", "Bitter"])
        XCTAssertEqual(rank(entries).first?.readyNowRecipeNames, ["Bitter", "Sweet"], "neutral profile: by name")
    }

    // MARK: - Exclusions and limit

    func testListedStylesAreExcluded() {
        let x = style("X"), y = style("Y")
        let result = rank([missing(recipe("A"), x), missing(recipe("B"), y)], listed: [x.id])
        XCTAssertEqual(result.map(\.style.name), ["Y"])
    }

    func testLimitTruncatesToTheTopSuggestions() {
        let styles = (1...7).map { style("S\($0)") }
        let entries = styles.enumerated().map { offset, style in missing(recipe("R\(offset)"), style) }
        XCTAssertEqual(rank(entries).count, 5)
        XCTAssertEqual(rank(entries, limit: 2).count, 2)
        XCTAssertEqual(rank(entries, limit: 0).count, 0)
    }

    // MARK: - Real catalog

    private func catalog() throws -> (index: TaxonomyIndex, recipes: [Recipe]) {
        let index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        return (index, try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData()))
    }

    private func cabinet(_ names: [String], index: TaxonomyIndex) throws -> [CabinetItem] {
        try names.map { name in
            CabinetItem.make(from: try XCTUnwrap(index.stylesById.values.first { $0.name == name }), index: index)
        }
    }

    func testLastWordCabinetSuggestsGreenChartreuseAsReadyNow() throws {
        let (index, recipes) = try catalog()
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet(["London Dry Gin", "Lime Juice", "Maraschino Liqueur"], index: index), index: index)

        let chartreuse = try XCTUnwrap(rank(entries, limit: 100).first { $0.style.name == "Green Chartreuse" })
        XCTAssertGreaterThanOrEqual(chartreuse.readyNow, 1)
        XCTAssertTrue(chartreuse.readyNowRecipeNames.contains("Last Word"))
    }

    func testEmptyCabinetStillSuggestsInRankOrder() throws {
        let (index, recipes) = try catalog()
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)

        let result = rank(entries)
        XCTAssertEqual(result.count, 5)
        for (lhs, rhs) in zip(result, result.dropFirst()) {
            XCTAssertTrue(lhs.readyNow > rhs.readyNow || (lhs.readyNow == rhs.readyNow && lhs.movesCloser >= rhs.movesCloser),
                          "\(lhs.style.name) ranked above \(rhs.style.name)")
        }
    }
}
