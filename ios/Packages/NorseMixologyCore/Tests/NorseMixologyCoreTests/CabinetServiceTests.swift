import XCTest
import SwiftData
@testable import NorseMixologyCore

final class CabinetServiceTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([CabinetItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeItem(name: String = "Hendrick's Gin") -> CabinetItem {
        CabinetItem(
            ingredientStyleId: UUID(), ingredientFamilyId: UUID(), categoryId: UUID(),
            displayName: name, brand: "Hendrick's", style: "Contemporary Gin", family: "Gin", category: "Spirit",
            flavorProfile: FlavorProfile(sweetness: 0.2, bitterness: 0.1, smokiness: 0, citrus: 0.4, floral: 0.6, spice: 0.1, herbal: 0.5, fruity: 0.3, oaky: 0, abv: 41.4)
        )
    }

    func testAddInsertsItem() throws {
        let context = try makeInMemoryContext()
        let item = makeItem()
        CabinetService.add(item, context: context)
        XCTAssertEqual(CabinetService.allItems(context: context).count, 1)
    }

    func testRemoveDeletesItem() throws {
        let context = try makeInMemoryContext()
        let item = makeItem()
        CabinetService.add(item, context: context)
        CabinetService.remove(item, context: context)
        XCTAssertEqual(CabinetService.allItems(context: context).count, 0)
    }

    func testContainsReflectsStyleId() throws {
        let context = try makeInMemoryContext()
        let item = makeItem()
        XCTAssertFalse(CabinetService.contains(styleId: item.ingredientStyleId, context: context))
        CabinetService.add(item, context: context)
        XCTAssertTrue(CabinetService.contains(styleId: item.ingredientStyleId, context: context))
    }

    func testAllItemsSortedByCategoryThenName() throws {
        let context = try makeInMemoryContext()
        let gin = makeItem(name: "Hendrick's Gin")
        let lime = CabinetItem(
            ingredientStyleId: UUID(), ingredientFamilyId: UUID(), categoryId: UUID(),
            displayName: "Lime", brand: nil, style: "Fresh Lime", family: "Citrus", category: "Fruit",
            flavorProfile: FlavorProfile(sweetness: 0.1, bitterness: 0.1, smokiness: 0, citrus: 0.9, floral: 0, spice: 0, herbal: 0, fruity: 0.2, oaky: 0, abv: 0)
        )
        CabinetService.add(lime, context: context)
        CabinetService.add(gin, context: context)
        let items = CabinetService.allItems(context: context)
        XCTAssertEqual(items.map(\.category), ["Fruit", "Spirit"])
    }

    // MARK: - addAll (recipe "I have all of these")

    private func taxonomyIndex() throws -> TaxonomyIndex {
        TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
    }

    private func style(_ name: String, in index: TaxonomyIndex) throws -> IngredientStyle {
        try XCTUnwrap(index.stylesById.values.first { $0.name == name }, "no style named \(name)")
    }

    func testAddAllInsertsEveryStyleAndReturnsTheCount() throws {
        let context = try makeInMemoryContext()
        let index = try taxonomyIndex()
        let styles = [try style("London Dry Gin", in: index), try style("Lime Juice", in: index)]

        let added = CabinetService.addAll(styles, index: index, context: context)

        XCTAssertEqual(added, 2)
        let items = CabinetService.allItems(context: context)
        XCTAssertEqual(Set(items.map(\.ingredientStyleId)), Set(styles.map(\.id)))
        XCTAssertTrue(items.allSatisfy { $0.brand == nil }, "bulk add never invents a brand")
    }

    func testAddAllSkipsStylesAlreadyOwned() throws {
        let context = try makeInMemoryContext()
        let index = try taxonomyIndex()
        let gin = try style("London Dry Gin", in: index)
        let lime = try style("Lime Juice", in: index)
        CabinetService.add(CabinetItem.make(from: gin, index: index, brand: "Tanqueray"), context: context)

        let added = CabinetService.addAll([gin, lime], index: index, context: context)

        XCTAssertEqual(added, 1)
        let items = CabinetService.allItems(context: context)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first { $0.ingredientStyleId == gin.id }?.brand, "Tanqueray", "the existing branded item is untouched")
    }

    func testAddAllIgnoresDuplicatesInTheInput() throws {
        let context = try makeInMemoryContext()
        let index = try taxonomyIndex()
        let gin = try style("London Dry Gin", in: index)

        XCTAssertEqual(CabinetService.addAll([gin, gin], index: index, context: context), 1)
        XCTAssertEqual(CabinetService.allItems(context: context).count, 1)
    }

    func testAddAllWithNothingToAddReturnsZero() throws {
        let context = try makeInMemoryContext()
        let index = try taxonomyIndex()

        XCTAssertEqual(CabinetService.addAll([], index: index, context: context), 0)
        XCTAssertTrue(CabinetService.allItems(context: context).isEmpty)
    }
}
