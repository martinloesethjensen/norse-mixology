import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Recipe Take spec §2/§4: storage rules, limits, empty-take deletion, migration.
final class RecipeTakeServiceTests: XCTestCase {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private static let schema = Schema([CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self, RecipeTake.self, RecipePhoto.self])

    private func makeStore() throws -> Store {
        let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        return Store(container: container, context: ModelContext(container))
    }

    private func makeRecipe(_ name: String = "Negroni") -> Recipe {
        Recipe(id: UUID(), name: name, description: "", glassType: .rocks, method: .build, ingredients: [], steps: [],
               flavorProfile: FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0),
               tags: [], difficulty: .easy, imageURL: nil)
    }

    /// Stand-in photo bytes: the service stores bytes and never decodes them.
    private let bytes = Data([0xFF, 0xD8, 0x01])

    // MARK: - Rating

    func testSettingARatingCreatesATakeWithTheCachedRecipeName() throws {
        let store = try makeStore()
        let recipe = makeRecipe("Negroni")

        try RecipeTakeService.setRating(4, for: recipe, context: store.context)

        let take = try XCTUnwrap(RecipeTakeService.take(for: recipe.id, context: store.context))
        XCTAssertEqual(take.rating, 4)
        XCTAssertEqual(take.recipeName, "Negroni")
    }

    func testRatingsOutsideZeroToFiveAreRejectedAndNothingIsStored() throws {
        let store = try makeStore()
        let recipe = makeRecipe()

        for invalid in [-1, 6, 99] {
            XCTAssertThrowsError(try RecipeTakeService.setRating(invalid, for: recipe, context: store.context)) { error in
                XCTAssertEqual(error as? TakeError, .invalidRating)
            }
        }
        XCTAssertNil(RecipeTakeService.take(for: recipe.id, context: store.context))
    }

    func testClearingTheOnlyRatingDeletesTheTake() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        try RecipeTakeService.setRating(4, for: recipe, context: store.context)

        try RecipeTakeService.setRating(0, for: recipe, context: store.context)

        XCTAssertNil(RecipeTakeService.take(for: recipe.id, context: store.context))
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<RecipeTake>()), 0)
    }

    func testSettingZeroWhenThereIsNoTakeDoesNothing() throws {
        let store = try makeStore()
        let recipe = makeRecipe()

        try RecipeTakeService.setRating(0, for: recipe, context: store.context)

        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<RecipeTake>()), 0)
    }

    // MARK: - Notes

    func testNotesAreSavedAndTrimmedToTheLimit() throws {
        let store = try makeStore()
        let recipe = makeRecipe()

        try RecipeTakeService.setNotes("Less vermouth.", for: recipe, context: store.context)
        XCTAssertEqual(RecipeTakeService.take(for: recipe.id, context: store.context)?.notes, "Less vermouth.")

        try RecipeTakeService.setNotes(String(repeating: "x", count: 2_500), for: recipe, context: store.context)
        XCTAssertEqual(RecipeTakeService.take(for: recipe.id, context: store.context)?.notes.count, TakeLimits.maxNotesLength)
    }

    func testWhitespaceOnlyNotesCountAsEmpty() throws {
        let store = try makeStore()
        let recipe = makeRecipe()

        try RecipeTakeService.setNotes("  \n \t ", for: recipe, context: store.context)
        XCTAssertNil(RecipeTakeService.take(for: recipe.id, context: store.context), "no take for blank notes alone")

        try RecipeTakeService.setRating(3, for: recipe, context: store.context)
        try RecipeTakeService.setNotes("   ", for: recipe, context: store.context)
        XCTAssertEqual(RecipeTakeService.take(for: recipe.id, context: store.context)?.notes, "")
    }

    func testClearingNotesKeepsTheTakeWhileARatingRemains() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        try RecipeTakeService.setRating(5, for: recipe, context: store.context)
        try RecipeTakeService.setNotes("Perfect.", for: recipe, context: store.context)

        try RecipeTakeService.setNotes("", for: recipe, context: store.context)

        let take = try XCTUnwrap(RecipeTakeService.take(for: recipe.id, context: store.context))
        XCTAssertEqual(take.rating, 5)
        XCTAssertEqual(take.notes, "")
    }

    func testOnlyOneTakePerRecipe() throws {
        let store = try makeStore()
        let recipe = makeRecipe()

        try RecipeTakeService.setRating(2, for: recipe, context: store.context)
        try RecipeTakeService.setNotes("Hmm.", for: recipe, context: store.context)
        try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: recipe, context: store.context)
        try RecipeTakeService.setRating(4, for: recipe, context: store.context)

        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<RecipeTake>()), 1)
    }

    // MARK: - Photos

    func testAddingAPhotoCreatesATakeAndPhotosComeBackOldestFirst() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        let late = Data([3]), middle = Data([2]), early = Data([1])

        try RecipeTakeService.addPhoto(full: bytes, thumbnail: late, for: recipe, context: store.context, date: Date(timeIntervalSince1970: 30))
        try RecipeTakeService.addPhoto(full: bytes, thumbnail: early, for: recipe, context: store.context, date: Date(timeIntervalSince1970: 10))
        try RecipeTakeService.addPhoto(full: bytes, thumbnail: middle, for: recipe, context: store.context, date: Date(timeIntervalSince1970: 20))

        XCTAssertNotNil(RecipeTakeService.take(for: recipe.id, context: store.context))
        XCTAssertEqual(RecipeTakeService.photos(for: recipe.id, context: store.context).map(\.thumbnail), [early, middle, late])
    }

    func testTheSeventhPhotoIsRefused() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        for _ in 0..<TakeLimits.maxPhotos {
            try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: recipe, context: store.context)
        }

        XCTAssertThrowsError(try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: recipe, context: store.context)) { error in
            XCTAssertEqual(error as? TakeError, .photoLimitReached)
        }
        XCTAssertEqual(RecipeTakeService.photos(for: recipe.id, context: store.context).count, 6)
    }

    func testRemovingTheLastPhotoDeletesAnOtherwiseEmptyTake() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        let id = try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: recipe, context: store.context)

        try RecipeTakeService.removePhoto(id: id, context: store.context)

        XCTAssertNil(RecipeTakeService.take(for: recipe.id, context: store.context))
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<RecipePhoto>()), 0)
    }

    func testRemovingAPhotoKeepsTheTakeWhenARatingExists() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        try RecipeTakeService.setRating(4, for: recipe, context: store.context)
        let id = try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: recipe, context: store.context)

        try RecipeTakeService.removePhoto(id: id, context: store.context)

        XCTAssertEqual(RecipeTakeService.take(for: recipe.id, context: store.context)?.rating, 4)
    }

    func testAPhotoCanBeLookedUpByIdWithItsFullBytes() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        let full = Data([9, 9, 9])
        let id = try RecipeTakeService.addPhoto(full: full, thumbnail: bytes, for: recipe, context: store.context)

        XCTAssertEqual(RecipeTakeService.photo(id: id, context: store.context)?.full, full)
        XCTAssertNil(RecipeTakeService.photo(id: UUID(), context: store.context))
    }

    // MARK: - Lists

    func testListDictionariesReflectRatingsNotesAndPhotos() throws {
        let store = try makeStore()
        let rated = makeRecipe("A"), noted = makeRecipe("B"), photographed = makeRecipe("C")
        try RecipeTakeService.setRating(5, for: rated, context: store.context)
        try RecipeTakeService.setNotes("note", for: noted, context: store.context)
        try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: photographed, context: store.context)
        try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: photographed, context: store.context)

        XCTAssertEqual(RecipeTakeService.ratings(context: store.context), [rated.id: 5])
        XCTAssertEqual(RecipeTakeService.recipeIdsWithNotes(context: store.context), [noted.id])
        XCTAssertEqual(RecipeTakeService.photoCounts(context: store.context), [photographed.id: 2])
    }

    // MARK: - Catalog independence

    func testATakeSurvivesEvenIfItsRecipeIsNoLongerInAnyCatalog() throws {
        let store = try makeStore()
        let gone = makeRecipe("Discontinued Sour")
        try RecipeTakeService.setRating(3, for: gone, context: store.context)
        try RecipeTakeService.setNotes("Loved it.", for: gone, context: store.context)

        // Nothing here knows about the catalog; a fresh fetch still finds everything, readable by name.
        let take = try XCTUnwrap(RecipeTakeService.take(for: gone.id, context: store.context))
        XCTAssertEqual(take.recipeName, "Discontinued Sour")
        XCTAssertEqual(take.rating, 3)
        XCTAssertEqual(take.notes, "Loved it.")
    }

    // MARK: - Migration

    func testAnExistingStoreOpensWithTheTakeModelsAndKeepsItsData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let zero = FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)

        // A store as shipped before this release: cabinet, favourites and shopping list only.
        do {
            let oldSchema = Schema([CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self])
            let container = try ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: url)])
            let context = ModelContext(container)
            context.insert(CabinetItem(ingredientStyleId: UUID(), ingredientFamilyId: UUID(), categoryId: UUID(),
                                       displayName: "Gin", brand: nil, style: "Gin", family: "Gin", category: "Spirit", flavorProfile: zero))
            context.insert(FavouriteRecipe(recipeId: UUID(), recipeName: "Negroni"))
            context.insert(ShoppingItem(ingredientStyleId: UUID(), styleName: "Campari"))
            try context.save()
        }

        let container = try ModelContainer(for: Self.schema, configurations: [ModelConfiguration(schema: Self.schema, url: url)])
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CabinetItem>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FavouriteRecipe>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShoppingItem>()), 1)
        let recipe = makeRecipe()
        try RecipeTakeService.setRating(5, for: recipe, context: context)
        try RecipeTakeService.addPhoto(full: bytes, thumbnail: bytes, for: recipe, context: context)
        XCTAssertEqual(RecipeTakeService.ratings(context: context), [recipe.id: 5])
        XCTAssertEqual(RecipeTakeService.photos(for: recipe.id, context: context).count, 1)
    }
}
