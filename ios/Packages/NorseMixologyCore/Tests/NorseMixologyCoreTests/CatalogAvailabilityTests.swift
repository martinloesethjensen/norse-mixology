import XCTest
@testable import NorseMixologyCore

/// Recipe Catalog Browse spec §2/§4: every catalog recipe evaluated against the
/// cabinet, with "Ready" defined by the engine's own results.
final class CatalogAvailabilityTests: XCTestCase {
    private var index: TaxonomyIndex!
    private var recipes: [Recipe]!

    override func setUpWithError() throws {
        index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
    }

    private func style(_ name: String) throws -> IngredientStyle {
        try XCTUnwrap(index.stylesById.values.first { $0.name == name }, "no style named \(name)")
    }

    private func item(for style: IngredientStyle) -> CabinetItem {
        CabinetItem(ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                    displayName: style.name, brand: nil, style: style.name,
                    family: index.familyName(for: style), category: index.categoryName(for: style),
                    flavorProfile: style.flavorProfile)
    }

    private func cabinet(_ names: String...) throws -> [CabinetItem] {
        try names.map { item(for: try style($0)) }
    }

    private func entry(_ name: String, in entries: [CatalogEntry]) throws -> CatalogEntry {
        try XCTUnwrap(entries.first { $0.recipe.name == name }, "no entry for \(name)")
    }

    // MARK: - Parity with the engine

    func testReadyEntriesAreExactlyTheEngineResultsForSeveralCabinets() throws {
        let first30 = index.stylesById.values.sorted { $0.name < $1.name }.prefix(30).map { item(for: $0) }
        let cabinets: [[CabinetItem]] = [
            [],
            try cabinet("London Dry Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth"),
            try cabinet("London Dry Gin", "Lime Juice", "Raspberry Liqueur"),
            try cabinet("Rye Whiskey", "Angostura Bitters"),
            Array(first30),
        ]
        for cabinet in cabinets {
            let engineIds = Set(MatchingService.match(cabinet: cabinet, recipes: recipes, index: index).map(\.id))
            let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: cabinet, index: index)
            XCTAssertEqual(Set(entries.filter { $0.tier == .ready }.map(\.id)), engineIds)
            for entry in entries {
                XCTAssertEqual(entry.match != nil, engineIds.contains(entry.id))
                if entry.match != nil { XCTAssertTrue(entry.missing.isEmpty, "\(entry.recipe.name) is ready but lists missing") }
            }
        }
    }

    func testEveryCatalogRecipeGetsOneEntryInCatalogOrder() throws {
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: try cabinet("London Dry Gin"), index: index)
        XCTAssertEqual(entries.map(\.id), recipes.map(\.id))
    }

    // MARK: - Missing ingredients

    func testLastWordIsMissingOnlyGreenChartreuse() throws {
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("London Dry Gin", "Lime Juice", "Raspberry Liqueur"), index: index)
        let lastWord = try entry("Last Word", in: entries)
        XCTAssertNil(lastWord.match)
        XCTAssertEqual(lastWord.missing.map(\.name), ["Green Chartreuse"])
        XCTAssertEqual(lastWord.tier, .missing1)
    }

    func testAddingTheMissingIngredientMovesTheRecipeToReady() throws {
        let entries = CatalogAvailability.evaluate(
            recipes: recipes,
            cabinet: try cabinet("London Dry Gin", "Lime Juice", "Raspberry Liqueur", "Green Chartreuse"),
            index: index)
        let lastWord = try entry("Last Word", in: entries)
        XCTAssertNotNil(lastWord.match)
        XCTAssertTrue(lastWord.missing.isEmpty)
        XCTAssertEqual(lastWord.tier, .ready)
    }

    func testGarnishesAndOptionalIngredientsAreNeverMissing() throws {
        // Negroni = gin + sweet vermouth + Bitter Aperitif + orange wheel (garnish).
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("London Dry Gin", "Sweet/Rosso Vermouth"), index: index)
        XCTAssertEqual(try entry("Negroni", in: entries).missing.map(\.name), ["Bitter Aperitif"])
        for entry in entries {
            for missing in entry.missing {
                let ingredient = try XCTUnwrap(entry.recipe.ingredients.first { $0.ingredientStyleId == missing.id })
                XCTAssertFalse(ingredient.isOptional, "\(entry.recipe.name): optional \(missing.name) listed as missing")
                XCTAssertNotEqual(RoleDerivation.role(for: ingredient, style: missing, in: entry.recipe, index: index), .garnish)
            }
        }
    }

    func testMissingIsInRecipeOrder() throws {
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)
        for entry in entries {
            let recipeOrder = entry.recipe.ingredients.map(\.ingredientStyleId)
            let positions = entry.missing.map { style in recipeOrder.firstIndex(of: style.id)! }
            XCTAssertEqual(positions, positions.sorted(), entry.recipe.name)
        }
    }

    func testSubstitutionsAreReportedOnRecipesThatAreNotMakeableYet() throws {
        // Old Fashioned = Bourbon + Demerara Syrup + Angostura + orange wheel. Rye stands in for Bourbon.
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("Rye Whiskey", "Angostura Bitters"), index: index)
        let oldFashioned = try entry("Old Fashioned", in: entries)
        XCTAssertNil(oldFashioned.match)
        XCTAssertEqual(oldFashioned.missing.map(\.name), ["Demerara Syrup"])
        let sub = try XCTUnwrap(oldFashioned.substitutions.first { $0.required.name == "Bourbon" })
        XCTAssertEqual(sub.substitute.name, "Rye Whiskey")
        XCTAssertFalse(sub.note.isEmpty)
    }

    func testDuplicateStyleInARecipeIsListedOnce() throws {
        let gin = try style("London Dry Gin")
        let line = RecipeIngredient(ingredientStyleId: gin.id, amount: "30ml", preparation: nil, isOptional: false, substituteNotes: nil)
        let doubleGin = Recipe(id: UUID(), name: "Double Gin", description: "", glassType: .rocks, method: .stir,
                               ingredients: [line, line], steps: [], flavorProfile: gin.flavorProfile, tags: [],
                               difficulty: .easy, imageURL: nil)
        let entries = CatalogAvailability.evaluate(recipes: [doubleGin], cabinet: try cabinet("Lime Juice"), index: index)
        XCTAssertEqual(entries.first?.missing.map(\.name), ["London Dry Gin"])
    }

    // MARK: - Edge cases

    func testEmptyCabinetListsEveryRequiredIngredientAsMissingAndDropsNothing() throws {
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)
        XCTAssertEqual(entries.count, recipes.count)
        XCTAssertTrue(entries.allSatisfy { $0.match == nil })
        XCTAssertTrue(entries.allSatisfy { $0.substitutions.isEmpty })
        let negroni = try entry("Negroni", in: entries)
        XCTAssertEqual(negroni.missing.map(\.name), ["London Dry Gin", "Sweet/Rosso Vermouth", "Bitter Aperitif"])
    }

    func testGhostCabinetItemNeverActsAsASubstitute() throws {
        let londonDry = try style("London Dry Gin")
        let ghostGin = CabinetItem(ingredientStyleId: UUID(), ingredientFamilyId: londonDry.familyId, categoryId: londonDry.categoryId,
                                   displayName: "Discontinued Gin", brand: nil, style: "Discontinued Gin",
                                   family: "Gin", category: "Spirit", flavorProfile: londonDry.flavorProfile)
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("Sweet/Rosso Vermouth", "Bitter Aperitif") + [ghostGin], index: index)
        let negroni = try entry("Negroni", in: entries)
        XCTAssertEqual(negroni.missing.map(\.name), ["London Dry Gin"])
        XCTAssertTrue(negroni.substitutions.isEmpty)
    }

    func testRecipeIngredientMissingFromTheIndexDoesNotCrash() throws {
        let gin = try style("London Dry Gin")
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [item(for: gin)], index: TaxonomyIndex(categories: []))
        XCTAssertEqual(entries.count, recipes.count)
        XCTAssertTrue(entries.allSatisfy { $0.missing.isEmpty })
    }

    func testTierFollowsMissingCount() throws {
        let recipe = recipes[0]
        let a = try style("London Dry Gin"), b = try style("Lime Juice"), c = try style("Green Chartreuse")
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: [a]).tier, .missing1)
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: [a, b]).tier, .missing2)
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: [a, b, c]).tier, .missing3Plus)
        // Invariant-guard case: unmatched with nothing missing is never Ready.
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: []).tier, .missing1)
    }
}
