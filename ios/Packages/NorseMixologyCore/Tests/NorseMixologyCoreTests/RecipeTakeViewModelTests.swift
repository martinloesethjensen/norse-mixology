import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Recipe Take spec §2/§4: list dictionaries, star toggling, photo adding with
/// partial failure and the six-photo limit.
@MainActor
final class RecipeTakeViewModelTests: XCTestCase {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> Store {
        let schema = Schema([CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self, RecipeTake.self, RecipePhoto.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return Store(container: container, context: ModelContext(container))
    }

    private func makeRecipe(_ name: String = "Negroni") -> Recipe {
        Recipe(id: UUID(), name: name, description: "", glassType: .rocks, method: .build, ingredients: [], steps: [],
               flavorProfile: FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0),
               tags: [], difficulty: .easy, imageURL: nil)
    }

    private let photo = TestImages.jpeg(width: 800, height: 600)

    // MARK: - Rating

    func testTappingAStarSetsTheRatingAndTheSameStarAgainClearsIt() throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()

        vm.setRating(4, for: recipe)
        XCTAssertEqual(vm.rating(for: recipe.id), 4)
        XCTAssertEqual(vm.ratings, [recipe.id: 4])

        vm.setRating(2, for: recipe)
        XCTAssertEqual(vm.rating(for: recipe.id), 2)

        vm.setRating(2, for: recipe)
        XCTAssertEqual(vm.rating(for: recipe.id), 0)
        XCTAssertTrue(vm.ratings.isEmpty)
    }

    func testAnInvalidRatingIsReportedAndStoresNothing() throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()

        vm.setRating(9, for: recipe)

        XCTAssertEqual(vm.lastError, .invalidRating)
        XCTAssertTrue(vm.ratings.isEmpty)
        vm.clearError()
        XCTAssertNil(vm.lastError)
    }

    // MARK: - Notes

    func testNotesArePublishedAndTrimmed() throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()

        vm.setNotes("Less vermouth.", for: recipe)
        XCTAssertEqual(vm.notes(for: recipe.id), "Less vermouth.")
        XCTAssertEqual(vm.hasNotes, [recipe.id])

        vm.setNotes(String(repeating: "y", count: 2_100), for: recipe)
        XCTAssertEqual(vm.notes(for: recipe.id).count, TakeLimits.maxNotesLength)

        vm.setNotes("   ", for: recipe)
        XCTAssertTrue(vm.hasNotes.isEmpty)
    }

    // MARK: - Photos

    func testAddingPhotosProcessesAndStoresThem() async throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()

        let result = await vm.addPhotos([photo, photo], for: recipe)

        XCTAssertEqual(result, AddPhotosResult(added: 2, failed: 0, refusedForLimit: 0))
        XCTAssertEqual(vm.photoCounts, [recipe.id: 2])
        XCTAssertEqual(vm.photos(for: recipe.id).count, 2)
    }

    func testAnUnreadablePhotoIsReportedAndTheRestAreStillAdded() async throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()

        let result = await vm.addPhotos([photo, Data("garbage".utf8), photo], for: recipe)

        XCTAssertEqual(result, AddPhotosResult(added: 2, failed: 1, refusedForLimit: 0))
        XCTAssertEqual(vm.photoCounts[recipe.id], 2)
    }

    func testPhotosBeyondTheLimitAreRefusedNotSilentlyDropped() async throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()

        let first = await vm.addPhotos(Array(repeating: photo, count: 7), for: recipe)
        XCTAssertEqual(first, AddPhotosResult(added: 6, failed: 0, refusedForLimit: 1))
        XCTAssertEqual(vm.photoCounts[recipe.id], 6)

        let second = await vm.addPhotos([photo], for: recipe)
        XCTAssertEqual(second, AddPhotosResult(added: 0, failed: 0, refusedForLimit: 1))
        XCTAssertEqual(vm.photoCounts[recipe.id], 6)
    }

    func testStoredPhotosAreDownsampledAndTheFullImageIsLargerThanTheThumbnail() async throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()

        _ = await vm.addPhotos([TestImages.jpeg(width: 2_400, height: 1_800)], for: recipe)

        let item = try XCTUnwrap(vm.photos(for: recipe.id).first)
        let thumbnail = try XCTUnwrap(TestImages.pixelSize(of: item.thumbnail))
        XCTAssertEqual(max(thumbnail.width, thumbnail.height), TakeLimits.thumbnailMaxPixels)
        let fullData = try XCTUnwrap(vm.fullImage(id: item.id))
        let full = try XCTUnwrap(TestImages.pixelSize(of: fullData))
        XCTAssertEqual(max(full.width, full.height), TakeLimits.fullPhotoMaxPixels)
    }

    func testRemovingPhotosUpdatesCountsAndLeavesNoTraceWhenTheTakeIsEmpty() async throws {
        let vm = RecipeTakeViewModel(modelContext: try makeStore().context)
        let recipe = makeRecipe()
        _ = await vm.addPhotos([photo, photo], for: recipe)

        let ids = vm.photos(for: recipe.id).map(\.id)
        vm.removePhoto(id: ids[0])
        XCTAssertEqual(vm.photoCounts[recipe.id], 1)

        vm.removePhoto(id: ids[1])
        XCTAssertTrue(vm.photoCounts.isEmpty)
        XCTAssertTrue(vm.ratings.isEmpty)
        XCTAssertTrue(vm.hasNotes.isEmpty)
    }
}
