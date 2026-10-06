import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Shopping List spec §2/§4: storage, the shared cabinet-item builder, and
/// opening an existing store with the new model.
final class ShoppingServiceTests: XCTestCase {
    /// Keeps the container alive alongside its context for the whole test.
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

    // MARK: - ShoppingService

    func testAddStoresStyleIdCachedNameAndDate() throws {
        let store = try makeStore()
        let styleId = UUID()
        let date = Date(timeIntervalSince1970: 1_000)

        ShoppingService.add(styleId: styleId, styleName: "Campari", context: store.context, date: date)

        let saved = try XCTUnwrap(ShoppingService.all(context: store.context).first)
        XCTAssertEqual(saved.ingredientStyleId, styleId)
        XCTAssertEqual(saved.styleName, "Campari")
        XCTAssertEqual(saved.dateAdded, date)
    }

    func testAddingTheSameStyleTwiceDoesNotDuplicate() throws {
        let store = try makeStore()
        let styleId = UUID()

        ShoppingService.add(styleId: styleId, styleName: "Campari", context: store.context)
        ShoppingService.add(styleId: styleId, styleName: "Campari", context: store.context)

        XCTAssertEqual(ShoppingService.all(context: store.context).count, 1)
    }

    func testAllIsNewestFirst() throws {
        let store = try makeStore()
        ShoppingService.add(styleId: UUID(), styleName: "Old", context: store.context, date: Date(timeIntervalSince1970: 1))
        ShoppingService.add(styleId: UUID(), styleName: "New", context: store.context, date: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(ShoppingService.all(context: store.context).map(\.styleName), ["New", "Old"])
    }

    func testRemoveDeletesOnlyThatStyleAndContainsReflectsIt() throws {
        let store = try makeStore()
        let keep = UUID(), drop = UUID()
        ShoppingService.add(styleId: keep, styleName: "Keep", context: store.context)
        ShoppingService.add(styleId: drop, styleName: "Drop", context: store.context)

        ShoppingService.remove(styleId: drop, context: store.context)

        XCTAssertTrue(ShoppingService.contains(styleId: keep, context: store.context))
        XCTAssertFalse(ShoppingService.contains(styleId: drop, context: store.context))
        XCTAssertEqual(ShoppingService.all(context: store.context).map(\.styleName), ["Keep"])
    }

    // MARK: - CabinetItem.make / CabinetService.remove(id:)

    func testCabinetItemMakeSnapshotsTheStyle() throws {
        let gin = try style("London Dry Gin")
        let item = CabinetItem.make(from: gin, index: index)

        XCTAssertEqual(item.ingredientStyleId, gin.id)
        XCTAssertEqual(item.ingredientFamilyId, gin.familyId)
        XCTAssertEqual(item.categoryId, gin.categoryId)
        XCTAssertEqual(item.displayName, "London Dry Gin")
        XCTAssertNil(item.brand)
        XCTAssertEqual(item.style, "London Dry Gin")
        XCTAssertEqual(item.family, "Gin")
        XCTAssertEqual(item.category, "Spirit")
        XCTAssertEqual(item.flavorProfile, gin.flavorProfile)
    }

    func testCabinetItemMakeTrimsTheBrandAndTreatsBlankAsNone() throws {
        let gin = try style("London Dry Gin")

        let branded = CabinetItem.make(from: gin, index: index, brand: "  Tanqueray ")
        XCTAssertEqual(branded.brand, "Tanqueray")
        XCTAssertEqual(branded.displayName, "Tanqueray London Dry Gin")

        let blank = CabinetItem.make(from: gin, index: index, brand: "   ")
        XCTAssertNil(blank.brand)
        XCTAssertEqual(blank.displayName, "London Dry Gin")
    }

    func testCabinetServiceRemoveByIdDeletesOnlyThatItem() throws {
        let store = try makeStore()
        let keep = CabinetItem.make(from: try style("London Dry Gin"), index: index)
        let drop = CabinetItem.make(from: try style("Lime Juice"), index: index)
        CabinetService.add(keep, context: store.context)
        CabinetService.add(drop, context: store.context)

        CabinetService.remove(id: drop.id, context: store.context)

        XCTAssertEqual(CabinetService.allItems(context: store.context).map(\.style), ["London Dry Gin"])
    }

    // MARK: - Migration

    func testExistingCabinetAndFavouritesStoreOpensWithTheShoppingModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let gin = try style("London Dry Gin")

        // A store as shipped before this release: cabinet + favourites only.
        do {
            let oldSchema = Schema([CabinetItem.self, FavouriteRecipe.self])
            let container = try ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: url)])
            let context = ModelContext(container)
            context.insert(CabinetItem.make(from: gin, index: index))
            context.insert(FavouriteRecipe(recipeId: UUID(), recipeName: "Negroni"))
            try context.save()
        }

        let newSchema = Schema([CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self])
        let container = try ModelContainer(for: newSchema, configurations: [ModelConfiguration(schema: newSchema, url: url)])
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CabinetItem>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FavouriteRecipe>()), 1)
        ShoppingService.add(styleId: UUID(), styleName: "Campari", context: context)
        XCTAssertEqual(ShoppingService.all(context: context).count, 1)
    }
}
