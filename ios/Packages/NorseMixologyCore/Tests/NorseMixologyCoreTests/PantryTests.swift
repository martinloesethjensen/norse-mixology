import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Pantry Staples spec §2: staples count as owned for matching, never become
/// stored cabinet items, and are never suggested by Buy next.
final class PantryTests: XCTestCase {
    private let suiteName = "PantryStoreTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func catalog() throws -> (index: TaxonomyIndex, recipes: [Recipe]) {
        let index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        return (index, try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData()))
    }

    private func cabinet(_ names: [String], index: TaxonomyIndex) throws -> [CabinetItem] {
        try names.map { name in
            CabinetItem.make(from: try XCTUnwrap(index.stylesById.values.first { $0.name == name }), index: index)
        }
    }

    // MARK: - Store

    func testEmptyByDefault() {
        XCTAssertTrue(PantryStore.load(defaults: defaults).isEmpty)
    }

    func testRoundTrip() {
        PantryStore.save([.sugar, .lemonsAndLimes], defaults: defaults)
        XCTAssertEqual(PantryStore.load(defaults: defaults), [.sugar, .lemonsAndLimes])
    }

    func testUnknownStaplesAreDroppedNotTheWholePantry() {
        defaults.set(["sugar", "caviar"], forKey: "com.norsemixology.pantryStaples")
        XCTAssertEqual(PantryStore.load(defaults: defaults), [.sugar])
    }

    // MARK: - Catalog coverage

    func testEveryStapleNamesRealCatalogStyles() throws {
        let names = Set(try catalog().index.stylesById.values.map(\.name))
        for staple in PantryStaple.allCases {
            for name in staple.styleNames { XCTAssertTrue(names.contains(name), "\(staple): \(name)") }
        }
        let all = PantryStaple.allCases.flatMap(\.styleNames)
        XCTAssertEqual(all.count, Set(all).count, "a style belongs to one staple")
    }

    func testStyleIdsCoverOnlyTheChosenStaples() throws {
        let index = try catalog().index
        let ids = Pantry.styleIds(for: [.eggs], index: index)
        XCTAssertEqual(ids.compactMap { index.stylesById[$0]?.name }, ["Egg White"])
        XCTAssertTrue(Pantry.styleIds(for: [], index: index).isEmpty)
    }

    // MARK: - Effective cabinet

    func testNoStaplesLeavesTheCabinetAsIs() throws {
        let index = try catalog().index
        let owned = try cabinet(["Bourbon"], index: index)
        XCTAssertEqual(Pantry.effectiveCabinet(owned, staples: [], index: index).map(\.id), owned.map(\.id))
    }

    func testStaplesAddOneItemPerStyleTheCabinetLacks() throws {
        let index = try catalog().index
        let owned = try cabinet(["Bourbon", "Simple Syrup"], index: index)
        let effective = Pantry.effectiveCabinet(owned, staples: [.sugar], index: index)

        XCTAssertEqual(Array(effective.prefix(2)).map(\.id), owned.map(\.id), "real cabinet items come first, untouched")
        XCTAssertEqual(effective.dropFirst(2).map(\.style), ["Demerara Syrup", "Sugar Rim"], "owned Simple Syrup isn't duplicated")
        XCTAssertNil(effective.last?.modelContext, "pantry items are never inserted into SwiftData")
    }

    // MARK: - Matching and Buy next

    func testPantryMakesASourWithOnlyTheSpirit() throws {
        let (index, recipes) = try catalog()
        let rum = try cabinet(["White/Blanco Rum"], index: index)

        XCTAssertFalse(MatchingService.match(cabinet: rum, recipes: recipes, index: index).contains { $0.recipe.name == "Daiquiri" })

        let effective = Pantry.effectiveCabinet(rum, staples: [.sugar, .lemonsAndLimes], index: index)
        let daiquiri = try XCTUnwrap(MatchingService.match(cabinet: effective, recipes: recipes, index: index).first { $0.recipe.name == "Daiquiri" })
        XCTAssertEqual(daiquiri.matchType, .exact)
    }

    func testBuyNextNeverSuggestsAPantryStyle() throws {
        let (index, recipes) = try catalog()
        let staples = Set(PantryStaple.allCases)
        let effective = Pantry.effectiveCabinet(try cabinet(["London Dry Gin"], index: index), staples: staples, index: index)
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: effective, index: index)

        let suggested = Set(BuyNextRanking.rank(entries: entries, listedStyleIds: [], profile: .neutral, limit: 1_000).map(\.style.id))
        XCTAssertFalse(suggested.isEmpty)
        XCTAssertTrue(suggested.isDisjoint(with: Pantry.styleIds(for: staples, index: index)))
    }
}
