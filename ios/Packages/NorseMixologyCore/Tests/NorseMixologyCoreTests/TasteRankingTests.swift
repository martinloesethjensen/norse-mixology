import XCTest
@testable import NorseMixologyCore

final class TasteRankingTests: XCTestCase {
    private func flavor(
        sweetness: Double = 0.5, bitterness: Double = 0.5, smokiness: Double = 0.5,
        citrus: Double = 0.5, herbal: Double = 0.5, oaky: Double = 0
    ) -> FlavorProfile {
        FlavorProfile(
            sweetness: sweetness, bitterness: bitterness, smokiness: smokiness,
            citrus: citrus, floral: 0, spice: 0, herbal: herbal, fruity: 0, oaky: oaky, abv: 40
        )
    }

    private func recipe(name: String, flavorProfile: FlavorProfile) -> Recipe {
        Recipe(
            id: UUID(), name: name, description: "", glassType: .rocks, method: .stir,
            ingredients: [], steps: [], flavorProfile: flavorProfile, tags: [],
            difficulty: .easy, imageURL: nil
        )
    }

    private func result(
        name: String, flavorProfile: FlavorProfile,
        matchType: MatchType = .exact, substitutions: [SubstitutionDetail] = []
    ) -> RecipeMatchResult {
        RecipeMatchResult(
            recipe: recipe(name: name, flavorProfile: flavorProfile),
            matchScore: matchType == .exact ? 1.0 : 0.8,
            matchType: matchType,
            substitutions: substitutions
        )
    }

    func testSimilarityIgnoresUnquizzedAxes() {
        let a = flavor(oaky: 0.1)
        let b = flavor(oaky: 0.9)
        let profile = UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: true)
        XCTAssertEqual(TasteRanking.similarity(profile, to: a), TasteRanking.similarity(profile, to: b), accuracy: 0.0001)
    }

    func testReorderSortsSweeterRecipeFirstForSweetLeaningProfile() {
        let dry = result(name: "Dry", flavorProfile: flavor(sweetness: 0.1))
        let sweet = result(name: "Sweet", flavorProfile: flavor(sweetness: 0.9))
        let grouped = GroupedMatchResults(results: [dry, sweet])
        let profile = UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: true)

        let reordered = TasteRanking.reorder(grouped, toward: profile)

        XCTAssertEqual(reordered.perfect.map(\.recipe.name), ["Sweet", "Dry"])
    }

    func testReorderPreservesOrderWhenOnlyAnUnquizzedAxisDiffers() {
        let first = result(name: "First", flavorProfile: flavor(oaky: 0.1))
        let second = result(name: "Second", flavorProfile: flavor(oaky: 0.9))
        let grouped = GroupedMatchResults(results: [first, second])
        let profile = UserTasteProfile(bitterness: 0.9, hasCompletedOnboarding: true)

        let reordered = TasteRanking.reorder(grouped, toward: profile)

        XCTAssertEqual(reordered.perfect.map(\.recipe.name), ["First", "Second"])
    }

    func testReorderIsNoOpForUncompletedProfile() {
        let a = result(name: "A", flavorProfile: flavor(sweetness: 0.1))
        let b = result(name: "B", flavorProfile: flavor(sweetness: 0.9))
        let grouped = GroupedMatchResults(results: [a, b])
        let uncompleted = UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: false)

        XCTAssertEqual(TasteRanking.reorder(grouped, toward: .neutral), grouped)
        XCTAssertEqual(TasteRanking.reorder(grouped, toward: uncompleted), grouped)
    }

    func testReorderIsNoOpForSkipPathProfile() {
        let a = result(name: "A", flavorProfile: flavor(sweetness: 0.1))
        let b = result(name: "B", flavorProfile: flavor(sweetness: 0.9))
        let grouped = GroupedMatchResults(results: [a, b])
        let skipped = UserTasteProfile(hasCompletedOnboarding: true) // all axes default 0.5

        XCTAssertEqual(TasteRanking.reorder(grouped, toward: skipped), grouped)
    }
}
