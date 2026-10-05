import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Shopping List spec §2/§4: list rules, tick-off ordering and undo.
final class ShoppingListViewModelTests: XCTestCase {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private var index: TaxonomyIndex!

    override func setUpWithError() throws {
        index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
    }

    private func makeStore() throws -> Store {
        let schema = Schema([CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return Store(container: container, context: ModelContext(container))
    }

    private func style(_ name: String) throws -> IngredientStyle {
        try XCTUnwrap(index.stylesById.values.first { $0.name == name }, "no style named \(name)")
    }

    private func cabinetStyleIds(_ store: Store) -> Set<UUID> {
        Set(CabinetService.allItems(context: store.context).map(\.ingredientStyleId))
    }

    // MARK: - Adding

    func testAddReportsAddedThenAlreadyListed() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse")

        XCTAssertEqual(vm.add(chartreuse, cabinetStyleIds: []), .added)
        XCTAssertEqual(vm.add(chartreuse, cabinetStyleIds: []), .alreadyListed)
        XCTAssertEqual(vm.items.map(\.styleName), ["Green Chartreuse"])
        XCTAssertTrue(vm.contains(styleId: chartreuse.id))
        XCTAssertEqual(vm.listedStyleIds, [chartreuse.id])
    }

    func testAddRefusesAStyleAlreadyInTheCabinet() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let gin = try style("London Dry Gin")

        XCTAssertEqual(vm.add(gin, cabinetStyleIds: [gin.id]), .alreadyOwned)
        XCTAssertTrue(vm.isEmpty)
    }

    func testAddAllSkipsOwnedListedAndRepeatedStylesAndCountsWhatItAdded() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse"), bitter = try style("Bitter Aperitif")
        let gin = try style("London Dry Gin"), vermouth = try style("Sweet/Rosso Vermouth")
        vm.add(vermouth, cabinetStyleIds: [])

        let added = vm.addAll([chartreuse, bitter, chartreuse, gin, vermouth], cabinetStyleIds: [gin.id])

        XCTAssertEqual(added, 2)
        XCTAssertEqual(Set(vm.items.map(\.styleName)), ["Green Chartreuse", "Bitter Aperitif", "Sweet/Rosso Vermouth"])
    }

    func testRemoveByItemAndByStyleId() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse"), bitter = try style("Bitter Aperitif")
        vm.add(chartreuse, cabinetStyleIds: [])
        vm.add(bitter, cabinetStyleIds: [])

        vm.remove(styleId: chartreuse.id)
        XCTAssertEqual(vm.items.map(\.styleName), ["Bitter Aperitif"])
        vm.remove(try XCTUnwrap(vm.items.first))
        XCTAssertTrue(vm.isEmpty)
    }

    // MARK: - Owned items

    func testPruneOwnedRemovesItemsNowInTheCabinet() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse"), bitter = try style("Bitter Aperitif")
        vm.add(chartreuse, cabinetStyleIds: [])
        vm.add(bitter, cabinetStyleIds: [])

        vm.pruneOwned(cabinetStyleIds: [chartreuse.id])

        XCTAssertEqual(vm.items.map(\.styleName), ["Bitter Aperitif"])
    }

    func testInterruptedTickOffLeavesTheItemInBothAndPruneClearsIt() throws {
        let store = try makeStore()
        let chartreuse = try style("Green Chartreuse")
        // State after a crash between "cabinet add" and "list remove".
        CabinetService.add(CabinetItem.make(from: chartreuse, index: index), context: store.context)
        ShoppingService.add(styleId: chartreuse.id, styleName: chartreuse.name, context: store.context)
        let vm = ShoppingListViewModel(modelContext: store.context)
        XCTAssertEqual(vm.items.count, 1)

        vm.pruneOwned(cabinetStyleIds: cabinetStyleIds(store))

        XCTAssertTrue(vm.isEmpty)
        XCTAssertEqual(CabinetService.allItems(context: store.context).count, 1, "the bottle is never lost")
    }

    // MARK: - Tick-off and undo

    func testMarkBoughtMovesTheStyleIntoTheCabinetAndOffTheList() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse")
        vm.add(chartreuse, cabinetStyleIds: [])

        let receipt = try XCTUnwrap(vm.markBought(try XCTUnwrap(vm.items.first), index: index))

        let cabinet = CabinetService.allItems(context: store.context)
        XCTAssertEqual(cabinet.map(\.ingredientStyleId), [chartreuse.id])
        XCTAssertEqual(receipt.createdCabinetItemId, cabinet.first?.id)
        XCTAssertEqual(receipt.styleId, chartreuse.id)
        XCTAssertEqual(receipt.styleName, "Green Chartreuse")
        XCTAssertTrue(vm.isEmpty)
    }

    func testUndoRemovesTheCreatedCabinetItemAndRestoresTheListItem() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse")
        vm.add(chartreuse, cabinetStyleIds: [])
        let receipt = try XCTUnwrap(vm.markBought(try XCTUnwrap(vm.items.first), index: index))

        vm.undo(receipt)

        XCTAssertTrue(CabinetService.allItems(context: store.context).isEmpty)
        XCTAssertEqual(vm.items.map(\.ingredientStyleId), [chartreuse.id])
    }

    func testUndoAfterTheCabinetItemWasDeletedByHandStillRestoresTheList() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse")
        vm.add(chartreuse, cabinetStyleIds: [])
        let receipt = try XCTUnwrap(vm.markBought(try XCTUnwrap(vm.items.first), index: index))
        for item in CabinetService.allItems(context: store.context) {
            CabinetService.remove(item, context: store.context)
        }

        vm.undo(receipt)

        XCTAssertTrue(CabinetService.allItems(context: store.context).isEmpty)
        XCTAssertEqual(vm.items.map(\.ingredientStyleId), [chartreuse.id])
    }

    func testMarkBoughtWhenTheBottleIsAlreadyOwnedNeitherDuplicatesNorUndoesTheOwnedBottle() throws {
        let store = try makeStore()
        let chartreuse = try style("Green Chartreuse")
        CabinetService.add(CabinetItem.make(from: chartreuse, index: index), context: store.context)
        ShoppingService.add(styleId: chartreuse.id, styleName: chartreuse.name, context: store.context)
        let vm = ShoppingListViewModel(modelContext: store.context)

        let receipt = try XCTUnwrap(vm.markBought(try XCTUnwrap(vm.items.first), index: index))
        XCTAssertNil(receipt.createdCabinetItemId)
        XCTAssertEqual(CabinetService.allItems(context: store.context).count, 1)
        XCTAssertTrue(vm.isEmpty)

        vm.undo(receipt)
        XCTAssertEqual(CabinetService.allItems(context: store.context).count, 1, "undo never removes a bottle the tick didn't add")
    }

    // MARK: - Entries and ghosts

    func testEntriesPairItemsWithTheirStylesNewestFirst() throws {
        let store = try makeStore()
        let vm = ShoppingListViewModel(modelContext: store.context)
        let chartreuse = try style("Green Chartreuse"), bitter = try style("Bitter Aperitif")
        ShoppingService.add(styleId: chartreuse.id, styleName: chartreuse.name, context: store.context, date: Date(timeIntervalSince1970: 1))
        ShoppingService.add(styleId: bitter.id, styleName: bitter.name, context: store.context, date: Date(timeIntervalSince1970: 2))
        vm.refresh()

        let entries = vm.entries(in: index)

        XCTAssertEqual(entries.map(\.style?.name), ["Bitter Aperitif", "Green Chartreuse"])
        XCTAssertEqual(entries.map(\.id), [bitter.id, chartreuse.id])
    }

    func testGhostItemHasNoStyleAndCannotBeMarkedBought() throws {
        let store = try makeStore()
        ShoppingService.add(styleId: UUID(), styleName: "Discontinued Gin", context: store.context)
        let vm = ShoppingListViewModel(modelContext: store.context)

        let entry = try XCTUnwrap(vm.entries(in: index).first)
        XCTAssertNil(entry.style)
        XCTAssertEqual(entry.item.styleName, "Discontinued Gin")
        XCTAssertNil(vm.markBought(entry.item, index: index))
        XCTAssertEqual(vm.items.count, 1, "a ghost stays listed until the user removes it")
        XCTAssertTrue(CabinetService.allItems(context: store.context).isEmpty)
    }
}
