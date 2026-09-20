import XCTest
@testable import NorseMixologyCore

final class RecipePresentationTests: XCTestCase {
    // MARK: - Fixtures

    private func makeStyle(_ name: String, sweetness: Double = 0.2) -> IngredientStyle {
        IngredientStyle(
            id: UUID(),
            name: name,
            familyId: UUID(),
            categoryId: UUID(),
            exampleBrands: [],
            flavorProfile: FlavorProfile(sweetness: sweetness, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 40),
            abvMin: 38,
            abvMax: 42
        )
    }

    private func makeIngredient(_ style: IngredientStyle, amount: String = "30ml", isOptional: Bool = false) -> RecipeIngredient {
        RecipeIngredient(ingredientStyleId: style.id, amount: amount, preparation: nil, isOptional: isOptional, substituteNotes: nil)
    }

    private func makeRecipe(name: String = "Test Drink", ingredients: [RecipeIngredient]) -> Recipe {
        Recipe(
            id: UUID(),
            name: name,
            description: "",
            glassType: .coupe,
            method: .shake,
            ingredients: ingredients,
            steps: [],
            flavorProfile: FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0),
            tags: [],
            difficulty: .easy,
            imageURL: nil
        )
    }

    private func makeSubstitution(required: IngredientStyle, substitute: IngredientStyle) -> SubstitutionDetail {
        SubstitutionDetail(required: required, substitute: substitute, similarityScore: 0.8, note: "note", ratioHint: nil)
    }

    private func makeResult(
        name: String = "Test Drink",
        matchType: MatchType,
        score: Double? = nil,
        substitutions: [SubstitutionDetail] = [],
        ingredients: [RecipeIngredient] = []
    ) -> RecipeMatchResult {
        RecipeMatchResult(
            recipe: makeRecipe(name: name, ingredients: ingredients),
            matchScore: score ?? (matchType == .exact ? 1.0 : 0.8),
            matchType: matchType,
            substitutions: substitutions
        )
    }

    // MARK: - GroupedMatchResults

    func testGroupsExactPartialWithOneSubAndPartialWithManySubs() {
        let a = makeStyle("A"), b = makeStyle("B"), c = makeStyle("C"), d = makeStyle("D")
        let exact = makeResult(name: "Exact", matchType: .exact)
        let almost = makeResult(name: "Almost", matchType: .partial, substitutions: [makeSubstitution(required: a, substitute: b)])
        let exploring = makeResult(
            name: "Exploring",
            matchType: .partial,
            substitutions: [makeSubstitution(required: a, substitute: b), makeSubstitution(required: c, substitute: d)]
        )

        let grouped = GroupedMatchResults(results: [exact, almost, exploring])

        XCTAssertEqual(grouped.perfect.map(\.recipe.name), ["Exact"])
        XCTAssertEqual(grouped.almost.map(\.recipe.name), ["Almost"])
        XCTAssertEqual(grouped.exploring.map(\.recipe.name), ["Exploring"])
        XCTAssertFalse(grouped.isEmpty)
    }

    func testExactMatchStaysPerfectEvenWhenAnAcceptedSubstitutionIsPresent() {
        // A user "accept" override resolves at quality 1.0 → matchType .exact, but the
        // substitution is still reported. It must not drop into a lower group.
        let a = makeStyle("A"), b = makeStyle("B")
        let exactWithSub = makeResult(matchType: .exact, substitutions: [makeSubstitution(required: a, substitute: b)])

        let grouped = GroupedMatchResults(results: [exactWithSub])

        XCTAssertEqual(grouped.perfect.count, 1)
        XCTAssertTrue(grouped.almost.isEmpty)
        XCTAssertTrue(grouped.exploring.isEmpty)
    }

    func testGroupingPreservesEngineOrderWithinEachGroup() {
        let first = makeResult(name: "First", matchType: .exact)
        let second = makeResult(name: "Second", matchType: .exact)
        let third = makeResult(name: "Third", matchType: .exact)

        let grouped = GroupedMatchResults(results: [first, second, third])

        XCTAssertEqual(grouped.perfect.map(\.recipe.name), ["First", "Second", "Third"])
    }

    func testEmptyResultsProduceEmptyGroups() {
        let grouped = GroupedMatchResults(results: [])

        XCTAssertTrue(grouped.isEmpty)
        XCTAssertTrue(grouped.perfect.isEmpty && grouped.almost.isEmpty && grouped.exploring.isEmpty)
    }

    // MARK: - MatchBadgeState

    func testBadgeStateForExactMatch() {
        let state = MatchBadgeState(result: makeResult(matchType: .exact))

        XCTAssertEqual(state, .exact)
        XCTAssertEqual(state.label, "✓ All ingredients")
    }

    func testBadgeStateForSingleSubstitution() {
        let a = makeStyle("A"), b = makeStyle("B")
        let state = MatchBadgeState(result: makeResult(matchType: .partial, substitutions: [makeSubstitution(required: a, substitute: b)]))

        XCTAssertEqual(state, .substituted(count: 1))
        XCTAssertEqual(state.label, "1 sub needed")
    }

    func testBadgeStateForMultipleSubstitutions() {
        let a = makeStyle("A"), b = makeStyle("B"), c = makeStyle("C"), d = makeStyle("D")
        let state = MatchBadgeState(result: makeResult(
            matchType: .partial,
            substitutions: [makeSubstitution(required: a, substitute: b), makeSubstitution(required: c, substitute: d)]
        ))

        XCTAssertEqual(state, .substituted(count: 2))
        XCTAssertEqual(state.label, "2 subs needed")
    }

    // MARK: - RecipeAvailability

    func testAvailabilityMarksExactSubstitutedAndUnavailableIngredients() {
        let gin = makeStyle("Gin"), vodka = makeStyle("Vodka"), campari = makeStyle("Campari"), orange = makeStyle("Orange Wheel")
        let result = makeResult(
            matchType: .partial,
            substitutions: [makeSubstitution(required: gin, substitute: vodka)],
            ingredients: [
                makeIngredient(gin),
                makeIngredient(campari),
                makeIngredient(orange, isOptional: true),
            ]
        )

        // Cabinet holds the substitute (vodka) and campari, but not the optional orange wheel.
        let rows = RecipeAvailability.rows(for: result, cabinetStyleIds: [vodka.id, campari.id])

        XCTAssertEqual(rows.map(\.status), [.substituted, .exact, .unavailable])
        XCTAssertEqual(rows[0].substitution?.substitute.name, "Vodka")
        XCTAssertNil(rows[1].substitution)
        XCTAssertNil(rows[2].substitution)
    }

    func testAvailabilityPreservesRecipeIngredientOrderAndIdentity() {
        let a = makeStyle("A"), b = makeStyle("B"), c = makeStyle("C")
        let result = makeResult(matchType: .exact, ingredients: [makeIngredient(a), makeIngredient(b), makeIngredient(c)])

        let rows = RecipeAvailability.rows(for: result, cabinetStyleIds: [a.id, b.id, c.id])

        XCTAssertEqual(rows.map(\.ingredient.ingredientStyleId), [a.id, b.id, c.id])
        XCTAssertEqual(Set(rows.map(\.id)).count, 3, "each row needs a distinct id for ForEach")
    }

    func testSubstitutionTakesPrecedenceOverExactStyleInCabinet() {
        // A user "accept" override can substitute even when the exact style is also owned.
        let gin = makeStyle("Gin"), vodka = makeStyle("Vodka")
        let result = makeResult(
            matchType: .exact,
            substitutions: [makeSubstitution(required: gin, substitute: vodka)],
            ingredients: [makeIngredient(gin)]
        )

        let rows = RecipeAvailability.rows(for: result, cabinetStyleIds: [gin.id, vodka.id])

        XCTAssertEqual(rows.first?.status, .substituted)
    }

    // MARK: - Glass / method / difficulty presentation

    func testEveryGlassTypeMapsToASymbolAndLabel() {
        let all: [GlassType] = [.coupe, .rocks, .highball, .martini, .collins, .hurricane, .flute, .mug, .wineGlass]

        for glass in all {
            XCTAssertFalse(glass.symbolName.isEmpty, "\(glass) needs an SF Symbol")
            XCTAssertFalse(glass.displayName.isEmpty, "\(glass) needs a display name")
        }
    }

    func testGlassSymbolsFollowPhaseFourMapping() {
        XCTAssertEqual(GlassType.coupe.symbolName, "wineglass")
        XCTAssertEqual(GlassType.martini.symbolName, "wineglass")
        XCTAssertEqual(GlassType.rocks.symbolName, "cup.and.saucer")
        XCTAssertEqual(GlassType.highball.symbolName, "cylinder")
        XCTAssertEqual(GlassType.collins.symbolName, "cylinder")
        XCTAssertEqual(GlassType.mug.symbolName, "mug")
    }

    func testMethodAndDifficultyDisplayNames() {
        XCTAssertEqual(Method.shake.displayName, "Shake")
        XCTAssertEqual(Method.throwMethod.displayName, "Throw")
        XCTAssertEqual(Difficulty.easy.displayName, "Easy")
        XCTAssertEqual(Difficulty.advanced.displayName, "Advanced")
    }

    // MARK: - Against the real bundled catalog

    private func loadBundledIndexAndRecipes() throws -> (TaxonomyIndex, [Recipe]) {
        let taxonomyURL = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        let recipesURL = try XCTUnwrap(Bundle.module.url(forResource: "recipes", withExtension: "json"))
        let categories = try IngredientTaxonomy.loadCategories(from: Data(contentsOf: taxonomyURL))
        let recipes = try IngredientTaxonomy.loadRecipes(from: Data(contentsOf: recipesURL))
        return (TaxonomyIndex(categories: categories), recipes)
    }

    private func cabinetItem(_ name: String, index: TaxonomyIndex) throws -> CabinetItem {
        let style = try XCTUnwrap(index.stylesById.values.first { $0.name == name })
        return CabinetItem(
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

    func testNegroniCabinetPutsNegroniInPerfectMatchWithAllRowsExact() throws {
        let (index, recipes) = try loadBundledIndexAndRecipes()
        let cabinet = try ["London Dry Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth"].map { try cabinetItem($0, index: index) }

        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index)
        let grouped = GroupedMatchResults(results: results)
        let negroni = try XCTUnwrap(grouped.perfect.first { $0.recipe.name == "Negroni" })

        let rows = RecipeAvailability.rows(for: negroni, cabinetStyleIds: Set(cabinet.map(\.ingredientStyleId)))
        let statusByName = Dictionary(uniqueKeysWithValues: rows.map { (index.stylesById[$0.ingredient.ingredientStyleId]?.name ?? "?", $0.status) })

        XCTAssertEqual(statusByName["London Dry Gin"], .exact)
        XCTAssertEqual(statusByName["Bitter Aperitif"], .exact)
        XCTAssertEqual(statusByName["Sweet/Rosso Vermouth"], .exact)
        // The seed data lists the orange wheel garnish as required, but the engine treats
        // garnishes as skippable — it stays in a perfect match and shows as unavailable.
        XCTAssertEqual(statusByName["Orange Wheel"], .unavailable)
    }

    func testSwappingGinForSameFamilyGinMovesNegroniToAlmostThereWithSubstitutionRow() throws {
        let (index, recipes) = try loadBundledIndexAndRecipes()
        // Recipe calls for London Dry Gin; the cabinet only has a different gin style.
        let cabinet = try ["Contemporary Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth"].map { try cabinetItem($0, index: index) }

        let results = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index)
        let grouped = GroupedMatchResults(results: results)
        let negroni = try XCTUnwrap(grouped.almost.first { $0.recipe.name == "Negroni" })

        let rows = RecipeAvailability.rows(for: negroni, cabinetStyleIds: Set(cabinet.map(\.ingredientStyleId)))
        let substituted = rows.filter { $0.status == .substituted }

        XCTAssertEqual(substituted.count, 1)
        XCTAssertEqual(substituted.first?.substitution?.required.name, "London Dry Gin")
        XCTAssertEqual(substituted.first?.substitution?.substitute.name, "Contemporary Gin")
        XCTAssertEqual(MatchBadgeState(result: negroni), .substituted(count: 1))
    }
}
