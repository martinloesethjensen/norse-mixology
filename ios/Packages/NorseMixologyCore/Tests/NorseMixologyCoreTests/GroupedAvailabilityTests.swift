import XCTest
@testable import NorseMixologyCore

final class GroupedAvailabilityTests: XCTestCase {
    private let style = IngredientStyle(
        id: UUID(), name: "Thing", familyId: UUID(), categoryId: UUID(), exampleBrands: [],
        flavorProfile: FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0),
        abvMin: 0, abvMax: 0)

    private func recipe(_ name: String, sweetness: Double = 0.5, bitterness: Double = 0.5) -> Recipe {
        Recipe(id: UUID(), name: name, description: "", glassType: .rocks, method: .stir, ingredients: [], steps: [],
               flavorProfile: FlavorProfile(sweetness: sweetness, bitterness: bitterness, smokiness: 0.5, citrus: 0.5,
                                            floral: 0, spice: 0, herbal: 0.5, fruity: 0, oaky: 0, abv: 20),
               tags: [], difficulty: .easy, imageURL: nil)
    }

    private func ready(_ recipe: Recipe, exact: Bool = true, score: Double = 1) -> CatalogEntry {
        CatalogEntry(recipe: recipe,
                     match: RecipeMatchResult(recipe: recipe, matchScore: score, matchType: exact ? .exact : .partial, substitutions: []),
                     substitutions: [], missing: [])
    }

    private func missing(_ recipe: Recipe, _ count: Int) -> CatalogEntry {
        CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: Array(repeating: style, count: count))
    }

    func testEntriesLandInTheirTier() {
        let grouped = GroupedAvailability(entries: [
            missing(recipe("C"), 3), ready(recipe("A")), missing(recipe("B"), 1), missing(recipe("D"), 2), missing(recipe("E"), 5),
        ], profile: .neutral)
        XCTAssertEqual(grouped.ready.map(\.recipe.name), ["A"])
        XCTAssertEqual(grouped.missing1.map(\.recipe.name), ["B"])
        XCTAssertEqual(grouped.missing2.map(\.recipe.name), ["D"])
        XCTAssertEqual(grouped.missing3Plus.map(\.recipe.name), ["C", "E"])
        XCTAssertEqual(grouped.entries(in: .missing2).map(\.recipe.name), ["D"])
        XCTAssertEqual(grouped.allIds.count, 5)
    }

    func testNeutralProfileOrdersReadyLikeTheEngineAndMissingByCountThenName() {
        let grouped = GroupedAvailability(entries: [
            ready(recipe("Partial"), exact: false, score: 0.8), ready(recipe("Zed")), ready(recipe("Alpha")),
            missing(recipe("Mojito"), 4), missing(recipe("Aviation"), 3), missing(recipe("Bramble"), 3),
        ], profile: .neutral)
        XCTAssertEqual(grouped.ready.map(\.recipe.name), ["Alpha", "Zed", "Partial"])
        XCTAssertEqual(grouped.missing3Plus.map(\.recipe.name), ["Aviation", "Bramble", "Mojito"])
    }

    func testActiveProfileRanksByTasteWithinEachTier() {
        let sweetTooth = UserTasteProfile(sweetness: 1, bitterness: 0, citrus: 0.5, smokiness: 0.5, herbal: 0.5, hasCompletedOnboarding: true)
        let grouped = GroupedAvailability(entries: [
            missing(recipe("Bitter", sweetness: 0, bitterness: 1), 1),
            missing(recipe("Sweet", sweetness: 1, bitterness: 0), 1),
            ready(recipe("BitterReady", sweetness: 0, bitterness: 1)),
            ready(recipe("SweetReady", sweetness: 1, bitterness: 0)),
        ], profile: sweetTooth)
        XCTAssertEqual(grouped.missing1.map(\.recipe.name), ["Sweet", "Bitter"])
        XCTAssertEqual(grouped.ready.map(\.recipe.name), ["SweetReady", "BitterReady"])
    }

    func testFilteringKeepsTiersAndOrder() throws {
        let index = TaxonomyIndex(categories: [])
        let grouped = GroupedAvailability(entries: [ready(recipe("Gimlet")), missing(recipe("Gin Fizz"), 1), missing(recipe("Mojito"), 1)],
                                          profile: .neutral)
        var filter = RecipeFilter()
        filter.query = "gi"
        let filtered = grouped.filtered(by: filter, index: index)
        XCTAssertEqual(filtered.ready.map(\.recipe.name), ["Gimlet"])
        XCTAssertEqual(filtered.missing1.map(\.recipe.name), ["Gin Fizz"])
        filter.query = "nothing like this"
        XCTAssertTrue(grouped.filtered(by: filter, index: index).isEmpty)
        XCTAssertEqual(grouped.filtered(by: RecipeFilter(), index: index), grouped)
    }

    func testChangingModeKeepsTheFilter() {
        var state = RecipeBrowseState()
        XCTAssertEqual(state.mode, .canMake)
        state.filter.toggle(.tag("sour"))
        state.mode = .all
        XCTAssertEqual(state.filter.criteria, [.tag("sour")])
        XCTAssertEqual(RecipeBrowseState.Mode(rawValue: "all"), .all, "raw values are persisted in @SceneStorage")
    }

    func testTasteRankingNoOpRuleIsShared() {
        XCTAssertFalse(TasteRanking.isActive(.neutral))
        XCTAssertFalse(TasteRanking.isActive(UserTasteProfile(hasCompletedOnboarding: true)), "Skip path")
        XCTAssertTrue(TasteRanking.isActive(UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: true)))
    }
}
