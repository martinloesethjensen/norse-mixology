# Recipe "My Take" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user keep a rating, notes and photos on any catalog recipe, on the device only, and see their stars on recipe cards and filter by them.

**Architecture:** The rules and storage live in the `NorseMixologyCore` package and are unit-tested with `swift test`: two SwiftData models (`RecipeTake`, `RecipePhoto`, photo bytes via external storage), a pure `PhotoProcessor` (ImageIO, downsamples without decoding the full bitmap), `RecipeTakeService`, and a `@MainActor @Observable RecipeTakeViewModel` injected at the app root like Favourites. The app target adds a "My take" section to the recipe screen, a blurred-photo header, markers on cards and rows, and a "My ratings" filter group. Catalog code and the matching engine are not touched.

**Tech Stack:** Swift 5.9, SwiftUI (iOS 17), SwiftData, ImageIO, PhotosUI (`PhotosPicker`), XCTest, xcodegen.

**Spec:** `docs/superpowers/specs/2026-10-06-recipe-take-design.md`

## Global Constraints

- Min iOS stays **17.0**; no new dependencies (ImageIO and PhotosUI are system frameworks).
- iOS only — do not touch `android/`.
- **Additive only:** do not change `MatchingService.swift`, `CatalogAvailability.swift`, `CatalogEntry.swift` or the catalog code. The only existing core types changed are `RecipeFilter` (new criterion, optional `ratings` argument with default `[:]`), `GroupedMatchResults.filtered` and `GroupedAvailability.filtered` (new defaulted `ratings:` argument).
- Limits, verbatim from the spec: rating **0…5** (0 = none; anything else rejected, not clamped); notes **at most 2,000 characters** (longer is trimmed); photos **at most 6** per recipe; full image **≤ 1600 px** longest edge, thumbnail **~320 px**, JPEG quality **0.8**.
- **A take with rating 0, empty notes (after trimming whitespace) and no photos does not exist.** One take per `recipeId`.
- Every take change is saved immediately (`context.save()`); a failed save surfaces as `TakeError.saveFailed`, never silently.
- A catalog update must never touch a take: nothing in the take code reads or deletes based on catalog contents.
- `@Observable` view models only — no Combine, no `ObservableObject`.
- Colours and font sizes only via `DesignTokens` / `.dsText(...)` (`.font(.caption)` / `.title2` on SF Symbols matches the existing icon buttons).
- Structured logging only (`AppLog`) — no `print`.
- Touch targets ≥ 44 pt; VoiceOver labels on every icon-only control; the star rating is one adjustable control; Reduce Transparency respected (header stays plain).
- All new UI strings end up in `ios/NorseMixology/Localizable.xcstrings` (run `ios/scripts/sync-strings.sh` after a CLI build).
- New app-target Swift files are registered by running `xcodegen generate` in `ios/`; verify each new file appears in a `SwiftCompile` line of the build log.
- Performance: the refresh pipeline including the ratings filter stays **< 100 ms**.

**Commands used throughout:**
- Core tests: `cd ios/Packages/NorseMixologyCore && swift test` (baseline on this branch: **253 tests, 0 failures** — confirm before Task 1). Filter with `swift test --filter <TestClass>`.
- App build (the `name=` destination is ambiguous on this machine — always use the id): `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build`
- Interactive simulator checks use the iOS Simulator tool, which only the controlling session can use; implementer subagents write "SIM CHECK NOT RUN".
- Stage named files only (`git add <paths>`); never `git add -A` / `git add .`.

---

## File Structure

**Core** (`ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/`)
- Create `Models/TakeLimits.swift` — the limits above.
- Create `Services/PhotoProcessor.swift` — `PhotoProcessor`, `PhotoError`.
- Create `Models/RecipeTake.swift`, `Models/RecipePhoto.swift` — the `@Model`s.
- Create `Services/RecipeTakeService.swift` — `TakeError`, `RecipeTakeService`.
- Create `ViewModels/RecipeTakeViewModel.swift` — `PhotoItem`, `AddPhotosResult`, `RecipeTakeViewModel`.
- Modify `Models/RecipeFilter.swift` — `MyRating`, `.myRating` criterion, `matches(..., ratings:)`, `GroupedMatchResults.filtered(..., ratings:)`.
- Modify `Models/GroupedAvailability.swift` — `filtered(..., ratings:)`.

**Core tests** (`ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/`)
- Create `TestImages.swift` (helper), `PhotoProcessorTests.swift`, `RecipeTakeServiceTests.swift`, `RecipeTakeViewModelTests.swift`.
- Modify `RecipeFilterTests.swift`, `HardeningTests.swift`.

**App** (`ios/NorseMixology/`)
- Modify `NorseMixologyApp.swift`, `ContentView.swift` (preview) — models in the container, view model injected.
- Modify `Recipes/RecipeBrowserViewModel.swift`, `Recipes/RecipeBrowserView.swift` — `ratings` plumbing.
- Modify `Recipes/RecipeFilterSheet.swift`, `Recipes/BrowseHeader.swift` — "My ratings" group and chip labels.
- Create `Components/RatingStars.swift` (read-only), `Components/TakeMarkers.swift` ("Note" / "N photos" line).
- Modify `Recipes/RecipeCardView.swift`, `Recipes/CatalogRowView.swift` — stars and markers.
- Create `Take/StarRatingControl.swift`, `Take/TakeNotesEditor.swift`, `Take/TakePhotoStrip.swift`, `Take/TakePhotoViewer.swift`, `Take/MyTakeSection.swift`, `Take/TakeHeaderBackground.swift`.
- Modify `Recipes/RecipeDetailView.swift` — My take section, header stars and background.

**Docs:** `NORSE_MIXOLOGY_BUILD.md` — "Recipe take (iOS)" section (Task 8).

---

### Task 1: `PhotoProcessor` and `TakeLimits`

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/TakeLimits.swift`
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/PhotoProcessor.swift`
- Create: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/TestImages.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/PhotoProcessorTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (ImageIO, UniformTypeIdentifiers).
- Produces:
  - `TakeLimits.maxNotesLength: Int` (2_000), `maxPhotos: Int` (6), `ratingRange: ClosedRange<Int>` (0...5), `fullPhotoMaxPixels: Int` (1_600), `thumbnailMaxPixels: Int` (320), `jpegQuality: Double` (0.8).
  - `enum PhotoError: Error, Equatable, Sendable { case unreadable }`
  - `PhotoProcessor.process(_ data: Data) throws -> (full: Data, thumbnail: Data)`
  - Test helpers `TestImages.jpeg(width:height:orientation:) -> Data` and `TestImages.pixelSize(of:) -> (width: Int, height: Int)?` (used by Tasks 1 and 3).

- [ ] **Step 1: Create the test helper and the failing tests**

Create `TestImages.swift`:

```swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Generated photos for tests — a solid-colour JPEG encodes fast even at 20 megapixels.
enum TestImages {
    /// A mid-grey JPEG, optionally tagged with an EXIF orientation (1…8).
    static func jpeg(width: Int, height: Int, orientation: Int? = nil) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}
```

Create `PhotoProcessorTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

/// Recipe Take spec §2/§4: photos are downsampled without decoding the full bitmap,
/// never upscaled, oriented upright, and bad data is refused rather than stored.
final class PhotoProcessorTests: XCTestCase {
    func testALargePhotoIsDownsampledToTheFullLimitAndAThumbnail() throws {
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 5_000, height: 4_000))

        let full = try XCTUnwrap(TestImages.pixelSize(of: result.full))
        XCTAssertEqual(full.width, 1_600)
        XCTAssertLessThanOrEqual(abs(full.height - 1_280), 1)

        let thumbnail = try XCTUnwrap(TestImages.pixelSize(of: result.thumbnail))
        XCTAssertEqual(thumbnail.width, 320)
        XCTAssertLessThanOrEqual(abs(thumbnail.height - 256), 1)
    }

    func testASmallPhotoIsNeverUpscaled() throws {
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 200, height: 100))

        let full = try XCTUnwrap(TestImages.pixelSize(of: result.full))
        XCTAssertEqual(full.width, 200)
        XCTAssertEqual(full.height, 100)
        let thumbnail = try XCTUnwrap(TestImages.pixelSize(of: result.thumbnail))
        XCTAssertEqual(thumbnail.width, 200)
    }

    func testTheEXIFOrientationIsApplied() throws {
        // 400×200 tagged "rotate 90°" is a portrait photo.
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 400, height: 200, orientation: 6))

        let full = try XCTUnwrap(TestImages.pixelSize(of: result.full))
        XCTAssertEqual(full.width, 200)
        XCTAssertEqual(full.height, 400)
    }

    func testDataThatIsNotAnImageIsRefused() {
        XCTAssertThrowsError(try PhotoProcessor.process(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? PhotoError, .unreadable)
        }
    }

    func testEmptyDataIsRefused() {
        XCTAssertThrowsError(try PhotoProcessor.process(Data())) { error in
            XCTAssertEqual(error as? PhotoError, .unreadable)
        }
    }

    func testOutputsAreJPEGAndTheThumbnailIsSmaller() throws {
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 3_000, height: 2_000))

        XCTAssertEqual(Array(result.full.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(Array(result.thumbnail.prefix(2)), [0xFF, 0xD8])
        XCTAssertLessThan(result.thumbnail.count, result.full.count)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter PhotoProcessorTests 2>&1 | grep -E "error" | head -3`
Expected: build FAILS — `cannot find 'PhotoProcessor' in scope`.

- [ ] **Step 3: Implement**

Create `Models/TakeLimits.swift`:

```swift
import Foundation

/// Limits for a recipe's "My take" (Recipe Take spec §2).
public enum TakeLimits {
    /// 0 means "no rating".
    public static let ratingRange = 0...5
    public static let maxNotesLength = 2_000
    public static let maxPhotos = 6
    public static let fullPhotoMaxPixels = 1_600
    public static let thumbnailMaxPixels = 320
    public static let jpegQuality = 0.8
}
```

Create `Services/PhotoProcessor.swift`:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PhotoError: Error, Equatable, Sendable {
    /// Empty, corrupt, or not an image.
    case unreadable
}

/// Turns a picked photo into the two JPEGs the app stores: a full image
/// (longest edge ≤ 1600 px) and a thumbnail (≤ 320 px).
///
/// Uses ImageIO's thumbnail path, so a 48-megapixel photo is downsampled while
/// it is read and its full-size bitmap is never held in memory. Never upscales.
/// Alpha is flattened by the JPEG encoder (picked photos are photographs).
public enum PhotoProcessor {
    public static func process(_ data: Data) throws -> (full: Data, thumbnail: Data) {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw PhotoError.unreadable }

        let longestEdge = max(width, height)
        let full = try render(source, maxPixels: min(TakeLimits.fullPhotoMaxPixels, longestEdge))
        let thumbnail = try render(source, maxPixels: min(TakeLimits.thumbnailMaxPixels, longestEdge))
        return (full, thumbnail)
    }

    private static func render(_ source: CGImageSource, maxPixels: Int) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // apply the EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoError.unreadable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoError.unreadable
        }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: TakeLimits.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.unreadable }
        return output as Data
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter PhotoProcessorTests 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | head -5`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1`
Expected: `Executed 259 tests, with 0 failures` (253 + 6).

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/TakeLimits.swift \
        ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/PhotoProcessor.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/TestImages.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/PhotoProcessorTests.swift
git commit -m "Core: PhotoProcessor downsamples picked photos without decoding the full bitmap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `RecipeTake`, `RecipePhoto` and `RecipeTakeService`

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RecipeTake.swift`
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RecipePhoto.swift`
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/RecipeTakeService.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RecipeTakeServiceTests.swift`

**Interfaces:**
- Consumes: `TakeLimits` (Task 1), `Recipe`, `CabinetItem`, `FavouriteRecipe`, `ShoppingItem` (existing; the migration test builds an old store from the last three).
- Produces:
  - `@Model RecipeTake { id: UUID; recipeId: UUID; recipeName: String; rating: Int; notes: String; updatedAt: Date; init(id:recipeId:recipeName:rating:notes:updatedAt:) }`
  - `@Model RecipePhoto { id: UUID; recipeId: UUID; thumbnail: Data; full: Data (@Attribute(.externalStorage)); dateAdded: Date; init(id:recipeId:thumbnail:full:dateAdded:) }`
  - `enum TakeError: Error, Equatable, Sendable { case invalidRating, photoLimitReached, saveFailed }`
  - `RecipeTakeService` (all `static`, caller owns the context): `take(for:context:) -> RecipeTake?`, `setRating(_:for:context:date:) throws`, `setNotes(_:for:context:date:) throws`, `@discardableResult addPhoto(full:thumbnail:for:context:date:) throws -> UUID`, `removePhoto(id:context:) throws`, `photo(id:context:) -> RecipePhoto?`, `photos(for:context:) -> [RecipePhoto]` (oldest first), `ratings(context:) -> [UUID: Int]`, `recipeIdsWithNotes(context:) -> Set<UUID>`, `photoCounts(context:) -> [UUID: Int]`.

- [ ] **Step 1: Write the failing tests**

Create `RecipeTakeServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RecipeTakeServiceTests 2>&1 | grep -E "error" | head -3`
Expected: build FAILS — `cannot find 'RecipeTake' in scope`.

- [ ] **Step 3: Create the models**

`Models/RecipeTake.swift`:

```swift
import Foundation
import SwiftData

/// The user's own take on one catalog recipe: a rating and notes (photos are `RecipePhoto`s).
/// Keyed by `recipeId` like `FavouriteRecipe`; `recipeName` is cached so the take stays
/// readable if a later catalog drops the recipe. Never touched by catalog updates.
@Model
public final class RecipeTake {
    public var id: UUID
    // Defaults let SwiftData add this model to existing stores without a custom migration.
    public var recipeId: UUID = UUID()
    public var recipeName: String = ""
    /// 0 = not rated, otherwise 1…5.
    public var rating: Int = 0
    public var notes: String = ""
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), recipeId: UUID, recipeName: String, rating: Int = 0, notes: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.rating = rating
        self.notes = notes
        self.updatedAt = updatedAt
    }
}
```

`Models/RecipePhoto.swift`:

```swift
import Foundation
import SwiftData

/// One photo on a recipe. The ~320 px thumbnail is read by cards and the header;
/// the full image (≤ 1600 px) is stored externally and only read by the viewer.
@Model
public final class RecipePhoto {
    public var id: UUID
    public var recipeId: UUID = UUID()
    public var thumbnail: Data = Data()
    @Attribute(.externalStorage) public var full: Data = Data()
    public var dateAdded: Date = Date()

    public init(id: UUID = UUID(), recipeId: UUID, thumbnail: Data, full: Data, dateAdded: Date = Date()) {
        self.id = id
        self.recipeId = recipeId
        self.thumbnail = thumbnail
        self.full = full
        self.dateAdded = dateAdded
    }
}
```

- [ ] **Step 4: Create the service**

`Services/RecipeTakeService.swift`:

```swift
import Foundation
import SwiftData

public enum TakeError: Error, Equatable, Sendable {
    case invalidRating
    case photoLimitReached
    /// The change is still pending in the context; autosave will retry it.
    case saveFailed
}

/// SwiftData access for `RecipeTake` and `RecipePhoto` — the caller owns the
/// `ModelContext`, like `FavouritesService`. Every change is saved immediately;
/// a failed save is thrown, never swallowed. A take with no rating, no notes
/// and no photos is deleted, so there are never empty records.
public enum RecipeTakeService {
    public static func take(for recipeId: UUID, context: ModelContext) -> RecipeTake? {
        let descriptor = FetchDescriptor<RecipeTake>(predicate: #Predicate { $0.recipeId == recipeId })
        return (try? context.fetch(descriptor))?.first
    }

    /// 0 clears the rating; anything outside 0…5 is rejected, not clamped.
    public static func setRating(_ rating: Int, for recipe: Recipe, context: ModelContext, date: Date = Date()) throws {
        guard TakeLimits.ratingRange.contains(rating) else { throw TakeError.invalidRating }
        if rating == 0, take(for: recipe.id, context: context) == nil { return }
        let take = ensureTake(for: recipe, context: context)
        take.rating = rating
        take.updatedAt = date
        try finish(recipe.id, context: context)
    }

    /// Trimmed to `TakeLimits.maxNotesLength`; whitespace-only counts as empty.
    public static func setNotes(_ notes: String, for recipe: Recipe, context: ModelContext, date: Date = Date()) throws {
        let limited = String(notes.prefix(TakeLimits.maxNotesLength))
        let stored = limited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : limited
        if stored.isEmpty, take(for: recipe.id, context: context) == nil { return }
        let take = ensureTake(for: recipe, context: context)
        take.notes = stored
        take.updatedAt = date
        try finish(recipe.id, context: context)
    }

    @discardableResult
    public static func addPhoto(full: Data, thumbnail: Data, for recipe: Recipe, context: ModelContext, date: Date = Date()) throws -> UUID {
        guard photoCount(recipe.id, context: context) < TakeLimits.maxPhotos else { throw TakeError.photoLimitReached }
        let take = ensureTake(for: recipe, context: context)
        take.updatedAt = date
        let photo = RecipePhoto(recipeId: recipe.id, thumbnail: thumbnail, full: full, dateAdded: date)
        context.insert(photo)
        try finish(recipe.id, context: context)
        return photo.id
    }

    public static func removePhoto(id: UUID, context: ModelContext) throws {
        guard let photo = photo(id: id, context: context) else { return }
        let recipeId = photo.recipeId
        context.delete(photo)
        try finish(recipeId, context: context)
    }

    public static func photo(id: UUID, context: ModelContext) -> RecipePhoto? {
        let descriptor = FetchDescriptor<RecipePhoto>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Oldest first. Loads thumbnails but not the full images (those are read on demand by `photo(id:)`).
    public static func photos(for recipeId: UUID, context: ModelContext) -> [RecipePhoto] {
        var descriptor = FetchDescriptor<RecipePhoto>(
            predicate: #Predicate { $0.recipeId == recipeId },
            sortBy: [SortDescriptor(\.dateAdded)]
        )
        descriptor.propertiesToFetch = [\.id, \.recipeId, \.thumbnail, \.dateAdded]
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Lists (read by cards and rows, so no per-row queries)

    public static func ratings(context: ModelContext) -> [UUID: Int] {
        let descriptor = FetchDescriptor<RecipeTake>(predicate: #Predicate { $0.rating > 0 })
        let takes = (try? context.fetch(descriptor)) ?? []
        return Dictionary(takes.map { ($0.recipeId, $0.rating) }, uniquingKeysWith: { first, _ in first })
    }

    public static func recipeIdsWithNotes(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<RecipeTake>(predicate: #Predicate { $0.notes != "" })
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.recipeId))
    }

    public static func photoCounts(context: ModelContext) -> [UUID: Int] {
        var descriptor = FetchDescriptor<RecipePhoto>()
        descriptor.propertiesToFetch = [\.recipeId]
        var counts: [UUID: Int] = [:]
        for photo in (try? context.fetch(descriptor)) ?? [] {
            counts[photo.recipeId, default: 0] += 1
        }
        return counts
    }

    // MARK: - Internals

    private static func ensureTake(for recipe: Recipe, context: ModelContext) -> RecipeTake {
        if let existing = take(for: recipe.id, context: context) { return existing }
        let take = RecipeTake(recipeId: recipe.id, recipeName: recipe.name)
        context.insert(take)
        return take
    }

    private static func photoCount(_ recipeId: UUID, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<RecipePhoto>(predicate: #Predicate { $0.recipeId == recipeId })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Deletes the take when nothing is left in it, then saves.
    private static func finish(_ recipeId: UUID, context: ModelContext) throws {
        if let take = take(for: recipeId, context: context),
           take.rating == 0, take.notes.isEmpty, photoCount(recipeId, context: context) == 0 {
            context.delete(take)
        }
        do {
            try context.save()
        } catch {
            throw TakeError.saveFailed
        }
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RecipeTakeServiceTests 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | head -8`
Expected: `Executed 16 tests, with 0 failures`.

If the migration test fails with a SwiftData migration error, stop and report BLOCKED with the full error — do not add a `VersionedSchema`. If a `#Predicate` fails to compile on `$0.notes != ""` or `$0.rating > 0`, rewrite that one predicate as a plain `fetch()` plus `.filter` in Swift and say so in the report.

- [ ] **Step 6: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1`
Expected: `Executed 275 tests, with 0 failures` (259 + 16).

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RecipeTake.swift \
        ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RecipePhoto.swift \
        ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/RecipeTakeService.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RecipeTakeServiceTests.swift
git commit -m "Core: RecipeTake and RecipePhoto models with a service that never leaves empty takes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `RecipeTakeViewModel`

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/ViewModels/RecipeTakeViewModel.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RecipeTakeViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1 `PhotoProcessor`, `TakeLimits`, `TestImages`; Task 2 `RecipeTakeService`, `TakeError`.
- Produces:
  - `struct PhotoItem: Identifiable, Equatable, Sendable { id: UUID; thumbnail: Data }`
  - `struct AddPhotosResult: Equatable, Sendable { var added: Int; var failed: Int; var refusedForLimit: Int; init(added: Int = 0, failed: Int = 0, refusedForLimit: Int = 0) }`
  - `@MainActor @Observable final class RecipeTakeViewModel` — `init(modelContext:)`; observed `ratings: [UUID: Int]`, `hasNotes: Set<UUID>`, `photoCounts: [UUID: Int]`, `lastError: TakeError?`; `refresh()`, `clearError()`, `rating(for:)`, `setRating(_:for:)` (same value again clears), `notes(for:)`, `setNotes(_:for:)`, `photos(for:) -> [PhotoItem]`, `fullImage(id:) -> Data?`, `addPhotos(_:for:) async -> AddPhotosResult`, `removePhoto(id:)`.

- [ ] **Step 1: Write the failing tests**

Create `RecipeTakeViewModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RecipeTakeViewModelTests 2>&1 | grep -E "error" | head -3`
Expected: build FAILS — `cannot find 'RecipeTakeViewModel' in scope`.

- [ ] **Step 3: Implement**

Create `ViewModels/RecipeTakeViewModel.swift`:

```swift
import Foundation
import Observation
import SwiftData

public struct PhotoItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let thumbnail: Data
}

public struct AddPhotosResult: Equatable, Sendable {
    public var added: Int
    public var failed: Int
    public var refusedForLimit: Int

    public init(added: Int = 0, failed: Int = 0, refusedForLimit: Int = 0) {
        self.added = added
        self.failed = failed
        self.refusedForLimit = refusedForLimit
    }
}

/// App-wide state for the user's takes (Recipe Take spec §2). One instance is
/// injected at the app root, like `FavouritesViewModel`. The dictionaries are
/// what cards and rows read, so a list never queries the database per row.
/// `@MainActor` because it owns main-context writes and processes photos off
/// the main actor before applying them.
@MainActor
@Observable
public final class RecipeTakeViewModel {
    private let modelContext: ModelContext

    public private(set) var ratings: [UUID: Int] = [:]
    public private(set) var hasNotes: Set<UUID> = []
    public private(set) var photoCounts: [UUID: Int] = [:]
    /// The last failure, for the screen to report; cleared by `clearError()`.
    public private(set) var lastError: TakeError?

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    public func refresh() {
        ratings = RecipeTakeService.ratings(context: modelContext)
        hasNotes = RecipeTakeService.recipeIdsWithNotes(context: modelContext)
        photoCounts = RecipeTakeService.photoCounts(context: modelContext)
    }

    public func clearError() { lastError = nil }

    // MARK: - Rating

    public func rating(for recipeId: UUID) -> Int { ratings[recipeId] ?? 0 }

    /// Tapping the star that is already the rating clears it.
    public func setRating(_ tapped: Int, for recipe: Recipe) {
        let target = tapped == rating(for: recipe.id) ? 0 : tapped
        perform { try RecipeTakeService.setRating(target, for: recipe, context: modelContext) }
    }

    // MARK: - Notes

    public func notes(for recipeId: UUID) -> String {
        RecipeTakeService.take(for: recipeId, context: modelContext)?.notes ?? ""
    }

    public func setNotes(_ notes: String, for recipe: Recipe) {
        perform { try RecipeTakeService.setNotes(notes, for: recipe, context: modelContext) }
    }

    // MARK: - Photos

    public func photos(for recipeId: UUID) -> [PhotoItem] {
        RecipeTakeService.photos(for: recipeId, context: modelContext).map { PhotoItem(id: $0.id, thumbnail: $0.thumbnail) }
    }

    public func fullImage(id: UUID) -> Data? {
        RecipeTakeService.photo(id: id, context: modelContext)?.full
    }

    public func removePhoto(id: UUID) {
        perform { try RecipeTakeService.removePhoto(id: id, context: modelContext) }
    }

    /// Processes the picked photos off the main actor, then stores the readable
    /// ones (up to the free slots). Nothing is dropped silently: the result counts
    /// what was added, what could not be read, and what the limit refused.
    public func addPhotos(_ items: [Data], for recipe: Recipe) async -> AddPhotosResult {
        let free = max(0, TakeLimits.maxPhotos - (photoCounts[recipe.id] ?? 0))
        let accepted = Array(items.prefix(free))
        var result = AddPhotosResult(refusedForLimit: items.count - accepted.count)

        let processed: [(full: Data, thumbnail: Data)?] = await Task.detached(priority: .userInitiated) {
            accepted.map { try? PhotoProcessor.process($0) }
        }.value

        for entry in processed {
            guard let entry else {
                result.failed += 1
                continue
            }
            do {
                try RecipeTakeService.addPhoto(full: entry.full, thumbnail: entry.thumbnail, for: recipe, context: modelContext)
                result.added += 1
            } catch TakeError.photoLimitReached {
                result.refusedForLimit += 1
            } catch let error as TakeError {
                lastError = error
                result.failed += 1
            } catch {
                lastError = .saveFailed
                result.failed += 1
            }
        }
        refresh()
        return result
    }

    // MARK: - Internals

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch let error as TakeError {
            lastError = error
        } catch {
            lastError = .saveFailed
        }
        refresh()
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RecipeTakeViewModelTests 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | head -6`
Expected: `Executed 8 tests, with 0 failures`.

(8 tests: tap/clear, invalid rating, notes, add, unreadable, limit, downsampled, remove.)

- [ ] **Step 5: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1`
Expected: `Executed 283 tests, with 0 failures` (275 + 8).

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/ViewModels/RecipeTakeViewModel.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RecipeTakeViewModelTests.swift
git commit -m "Core: RecipeTakeViewModel — stars, notes and photos with partial-failure results

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: "My ratings" filter in core

**Files:**
- Modify: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RecipeFilter.swift`
- Modify: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/GroupedAvailability.swift`
- Modify (tests): `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RecipeFilterTests.swift`, `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/HardeningTests.swift`

**Interfaces:**
- Consumes: existing `RecipeFilter`, `GroupedMatchResults`, `GroupedAvailability`, `CatalogAvailability`, `RecipeMatchResult`.
- Produces:
  - `RecipeFilter.MyRating: Hashable, Sendable { case rated, fourOrMore; var displayName: String }` ("Rated", "4 stars or more")
  - `RecipeFilter.Criterion.myRating(MyRating)`
  - `RecipeFilter.matches(_ recipe: Recipe, index: TaxonomyIndex, ratings: [UUID: Int] = [:]) -> Bool`
  - `GroupedMatchResults.filtered(by:index:ratings:)` and `GroupedAvailability.filtered(by:index:ratings:)`, `ratings` defaulting to `[:]`.

- [ ] **Step 1: Write the failing tests**

Append to `RecipeFilterTests` (inside the class, before its final `}`). The class already has `index`, `recipes`, a private `names(_:)` and a private `filter(query:_:)` helper.

```swift
    // MARK: - My ratings

    private func ratedNames(_ criteria: RecipeFilter.Criterion..., ratings: [UUID: Int]) -> Set<String> {
        var filter = RecipeFilter()
        criteria.forEach { filter.toggle($0) }
        return Set(recipes.filter { filter.matches($0, index: index, ratings: ratings) }.map(\.name))
    }

    private func ratings(_ pairs: (String, Int)...) throws -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (name, stars) in pairs {
            result[try XCTUnwrap(recipes.first { $0.name == name }, "no recipe named \(name)").id] = stars
        }
        return result
    }

    func testRatedKeepsOnlyRatedRecipes() throws {
        let mine = try ratings(("Negroni", 2), ("Daiquiri", 5))
        XCTAssertEqual(ratedNames(.myRating(.rated), ratings: mine), ["Negroni", "Daiquiri"])
    }

    func testFourStarsOrMoreKeepsOnlyHighRatings() throws {
        let mine = try ratings(("Negroni", 3), ("Daiquiri", 4), ("Margarita", 5))
        XCTAssertEqual(ratedNames(.myRating(.fourOrMore), ratings: mine), ["Daiquiri", "Margarita"])
    }

    func testRatingCriteriaFormOneOrGroupAndCombineWithOtherKindsByAnd() throws {
        let mine = try ratings(("Negroni", 1), ("Daiquiri", 5))
        // Both in the group: rated OR 4+ is just "rated".
        XCTAssertEqual(ratedNames(.myRating(.rated), .myRating(.fourOrMore), ratings: mine), ["Negroni", "Daiquiri"])
        // AND with another kind: only rated recipes that are also stirred.
        let stirredAndRated = ratedNames(.myRating(.rated), .method(.stir), ratings: mine)
        XCTAssertTrue(stirredAndRated.isSubset(of: ["Negroni", "Daiquiri"]))
        XCTAssertEqual(stirredAndRated, Set(["Negroni", "Daiquiri"].filter { name in
            recipes.first { $0.name == name }?.method == .stir
        }))
    }

    func testWithoutARatingsDictionaryNothingCountsAsRated() {
        XCTAssertTrue(names(filter(.myRating(.rated))).isEmpty)
        XCTAssertTrue(names(filter(.myRating(.fourOrMore))).isEmpty)
    }

    func testGroupedFilteringPassesTheRatingsThrough() throws {
        let mine = try ratings(("Negroni", 5), ("Aviation", 2))
        var rated = RecipeFilter()
        rated.toggle(.myRating(.rated))

        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)
        let availability = GroupedAvailability(entries: entries, profile: .neutral).filtered(by: rated, index: index, ratings: mine)
        XCTAssertEqual(Set(availability.allIds), Set(mine.keys))

        let matches = recipes.map { RecipeMatchResult(recipe: $0, matchScore: 1, matchType: .exact, substitutions: []) }
        let grouped = GroupedMatchResults(results: matches).filtered(by: rated, index: index, ratings: mine)
        XCTAssertEqual(Set(grouped.perfect.map(\.id)), Set(mine.keys))
    }

    func testRatingChipLabels() {
        XCTAssertEqual(RecipeFilter.MyRating.rated.displayName, "Rated")
        XCTAssertEqual(RecipeFilter.MyRating.fourOrMore.displayName, "4 stars or more")
    }
```

Edit `HardeningTests.testRefreshPipelineForA30ItemCabinetIsWellUnder100ms` — directly after the existing line `let filtered = grouped.filtered(by: filter, index: index)` add (inside the timed region):

```swift
        let ratings = Dictionary(uniqueKeysWithValues: recipes.prefix(40).map { ($0.id, 4) })
        var ratingFilter = RecipeFilter()
        ratingFilter.toggle(.myRating(.fourOrMore))
        let rated = grouped.filtered(by: ratingFilter, index: index, ratings: ratings)
```

and after `XCTAssertFalse(filtered.isEmpty)` add `XCTAssertFalse(rated.isEmpty)`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter 'RecipeFilterTests|HardeningTests' 2>&1 | grep -E "error" | head -3`
Expected: build FAILS — `type 'RecipeFilter.Criterion' has no member 'myRating'`.

- [ ] **Step 3: Implement in `RecipeFilter.swift`**

Add the enum next to `Strength` (inside `RecipeFilter`):

```swift
    /// "My ratings" filter values (Recipe Take spec §2).
    public enum MyRating: Hashable, Sendable {
        case rated
        case fourOrMore

        public var displayName: String {
            switch self {
            case .rated: return "Rated"
            case .fourOrMore: return "4 stars or more"
            }
        }
    }
```

Add the criterion case in `Criterion`:

```swift
        case myRating(MyRating)
```

Change the matcher signatures and the bucket logic. Replace `public func matches(_ recipe: Recipe, index: TaxonomyIndex) -> Bool { ... }` with:

```swift
    public func matches(_ recipe: Recipe, index: TaxonomyIndex, ratings: [UUID: Int] = [:]) -> Bool {
        matchesQuery(recipe, index: index) && matchesCriteria(recipe, index: index, ratings: ratings)
    }
```

In `matchesCriteria`, change the signature to `private func matchesCriteria(_ recipe: Recipe, index: TaxonomyIndex, ratings: [UUID: Int]) -> Bool`, add `var myRatings: Set<MyRating> = []` with the other buckets, add `case .myRating(let rating): myRatings.insert(rating)` to the `switch`, and add after the difficulty check:

```swift
        if !myRatings.isEmpty {
            let stars = ratings[recipe.id] ?? 0
            let matchesAny = myRatings.contains { $0 == .rated ? stars >= 1 : stars >= 4 }
            if !matchesAny { return false }
        }
```

Change the grouped helper at the bottom of the file to:

```swift
    func filtered(by filter: RecipeFilter, index: TaxonomyIndex, ratings: [UUID: Int] = [:]) -> GroupedMatchResults {
        guard !filter.isEmpty else { return self }
        let keep = { (result: RecipeMatchResult) in filter.matches(result.recipe, index: index, ratings: ratings) }
        return GroupedMatchResults(results: perfect.filter(keep) + almost.filter(keep) + exploring.filter(keep))
    }
```

(Keep its `public extension GroupedMatchResults` wrapper and doc comment as they are.)

In `GroupedAvailability.swift`, change `filtered` to:

```swift
    public func filtered(by filter: RecipeFilter, index: TaxonomyIndex, ratings: [UUID: Int] = [:]) -> GroupedAvailability {
        guard !filter.isEmpty else { return self }
        let keep = { (entry: CatalogEntry) in filter.matches(entry.recipe, index: index, ratings: ratings) }
        return GroupedAvailability(ready: ready.filter(keep), missing1: missing1.filter(keep),
                                   missing2: missing2.filter(keep), missing3Plus: missing3Plus.filter(keep))
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter 'RecipeFilterTests|HardeningTests|GroupedAvailabilityTests' 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | tail -4`
Expected: 0 failures (the existing `RecipeFilterTests` plus 6 new ones).

If the app target fails to compile later because of a non-exhaustive switch over `Criterion`, that is Task 5's job (`BrowseHeader.label`).

- [ ] **Step 5: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1`
Expected: `Executed 289 tests, with 0 failures` (283 + 6).

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RecipeFilter.swift \
        ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/GroupedAvailability.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RecipeFilterTests.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/HardeningTests.swift
git commit -m "Core: 'My ratings' filter (Rated, 4 stars or more) with the ratings passed in

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: App wiring, list markers and the filter group

**Files:**
- Modify: `ios/NorseMixology/NorseMixologyApp.swift`
- Modify: `ios/NorseMixology/ContentView.swift` (preview only)
- Modify: `ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeBrowserView.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeFilterSheet.swift`
- Modify: `ios/NorseMixology/Recipes/BrowseHeader.swift`
- Create: `ios/NorseMixology/Components/RatingStars.swift`
- Create: `ios/NorseMixology/Components/TakeMarkers.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeCardView.swift`
- Modify: `ios/NorseMixology/Recipes/CatalogRowView.swift`
- Modify: `ios/NorseMixology.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Consumes: Task 2 models; Task 3 `RecipeTakeViewModel` (`ratings`, `hasNotes`, `photoCounts`); Task 4 `RecipeFilter.Criterion.myRating`, `RecipeFilter.MyRating`, `filtered(by:index:ratings:)`.
- Produces: `RecipeTakeViewModel` in the SwiftUI environment for every view; `RatingStars(rating:font:)` (read-only); `TakeMarkers(recipeId:)`; `RecipeBrowserViewModel.ratings: [UUID: Int]` kept in sync by the Recipes tab.

- [ ] **Step 1: Container and environment in `NorseMixologyApp.swift`**

Add a stored property after `shoppingListViewModel`:

```swift
    @State private var recipeTakeViewModel: RecipeTakeViewModel
```

Change the container line to:

```swift
            let container = try ModelContainer(for: CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self, RecipeTake.self, RecipePhoto.self)
```

After `_shoppingListViewModel = ...` add:

```swift
            _recipeTakeViewModel = State(initialValue: RecipeTakeViewModel(modelContext: container.mainContext))
```

After `.environment(shoppingListViewModel)` add `.environment(recipeTakeViewModel)`. Update the comment above the container to name the Take view model, and update the `loadCatalog` doc comment line listing what is persisted to: "only `CabinetItem`s, `FavouriteRecipe`s, `ShoppingItem`s, `RecipeTake`s and `RecipePhoto`s are persisted."

- [ ] **Step 2: Preview in `ContentView.swift`**

In `#Preview`, extend the `ModelContainer(for: ...)` list with `ShoppingItem.self, RecipeTake.self, RecipePhoto.self` if any are missing, and add `.environment(RecipeTakeViewModel(modelContext: container.mainContext))` after the `ShoppingListViewModel` line.

- [ ] **Step 3: `ratings` on the browser view model**

In `RecipeBrowserViewModel.swift` add next to `tasteProfile`:

```swift
    /// The user's ratings (recipe id → 1…5), kept in sync by the Recipes tab; the "My ratings" filter reads them.
    var ratings: [UUID: Int] = [:]
```

and change the two visible properties to pass them:

```swift
    var visibleGrouped: GroupedMatchResults { grouped.filtered(by: browseState.filter, index: index, ratings: ratings) }
    var visibleAvailability: GroupedAvailability { availability.filtered(by: browseState.filter, index: index, ratings: ratings) }
```

In `RecipeBrowserView.swift` add `@Environment(RecipeTakeViewModel.self) private var take` and, with the other `.onChange` modifiers on the root `Group`:

```swift
        .onChange(of: take.ratings, initial: true) {
            viewModel.ratings = take.ratings
            viewModel.clearSelectionIfHidden()
        }
```

- [ ] **Step 4: Filter group and chip label**

In `RecipeFilterSheet.swift`, after the "Difficulty" section line add:

```swift
                section("My ratings", [RecipeFilter.Criterion.myRating(.rated), .myRating(.fourOrMore)])
```

In `BrowseHeader.swift`'s `label(familyNamesById:)` switch add:

```swift
        case .myRating(let rating): return rating.displayName
```

- [ ] **Step 5: Create `Components/RatingStars.swift`**

```swift
import SwiftUI

/// The user's rating, read-only: five stars, filled up to the rating. One
/// accessibility element ("Rated, 4 of 5"). Interactive rating is `StarRatingControl`.
struct RatingStars: View {
    let rating: Int
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(font)
                    .foregroundStyle(star <= rating ? DesignTokens.accent : DesignTokens.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating")
        .accessibilityValue("\(rating) of 5")
    }
}
```

- [ ] **Step 6: Create `Components/TakeMarkers.swift`**

```swift
import SwiftUI

/// A quiet "Note" / "N photos" line for recipes the user has added to. Draws
/// nothing for recipes they haven't, so untouched lists look exactly as before.
struct TakeMarkers: View {
    let recipeId: UUID

    @Environment(RecipeTakeViewModel.self) private var take

    var body: some View {
        let hasNote = take.hasNotes.contains(recipeId)
        let photos = take.photoCounts[recipeId] ?? 0
        let photoLabel: LocalizedStringKey = photos == 1 ? "1 photo" : "\(photos) photos"

        if hasNote || photos > 0 {
            HStack(spacing: 10) {
                if hasNote {
                    Label("Note", systemImage: "note.text")
                }
                if photos > 0 {
                    Label(photoLabel, systemImage: "photo")
                }
            }
            .dsText(.body)
            .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
```

- [ ] **Step 7: Stars and markers on cards and rows**

In `RecipeCardView.swift`: add `@Environment(RecipeTakeViewModel.self) private var take`. In the name row, directly before the `if favourites.isFavourited(recipe.id) { ... }` heart, add:

```swift
                if let stars = take.ratings[recipe.id] {
                    RatingStars(rating: stars)
                }
```

and directly after the `FlavorNoteChips(...)` line add `TakeMarkers(recipeId: recipe.id)`.

In `CatalogRowView.swift`: add `@Environment(RecipeTakeViewModel.self) private var take`. Directly before the heart `if favourites.isFavourited(entry.recipe.id) { ... }` add:

```swift
            if let stars = take.ratings[entry.recipe.id] {
                RatingStars(rating: stars)
            }
```

and after its `FlavorNoteChips(...)....padding(.top, 4)` line add `TakeMarkers(recipeId: entry.recipe.id)`.

- [ ] **Step 8: Register files and build**

```bash
cd ios && xcodegen generate && git diff --stat NorseMixology.xcodeproj
```
Expected: `project.pbxproj` changes only for the two new files.

```bash
cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tee "${TMPDIR:-/tmp}/nm-build.log" | grep -E 'error:|BUILD'
for f in RatingStars TakeMarkers; do grep -q "SwiftCompile.*$f\.swift" "${TMPDIR:-/tmp}/nm-build.log" && echo "OK $f" || echo "MISSING $f"; done
```
Expected: `** BUILD SUCCEEDED **`, `OK` twice.

- [ ] **Step 9: Simulator check (controller only)**

With nothing rated, lists look exactly as before. In `swift test`-less terms: this task adds no way to create a take yet (Task 6), so verify only that the app launches, both recipe modes render, and the Filters sheet shows a "My ratings" group; choosing "Rated" shows "No recipes match". Implementers: write "SIM CHECK NOT RUN".

- [ ] **Step 10: Commit**

```bash
git add ios/NorseMixology/NorseMixologyApp.swift ios/NorseMixology/ContentView.swift \
        ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift ios/NorseMixology/Recipes/RecipeBrowserView.swift \
        ios/NorseMixology/Recipes/RecipeFilterSheet.swift ios/NorseMixology/Recipes/BrowseHeader.swift \
        ios/NorseMixology/Recipes/RecipeCardView.swift ios/NorseMixology/Recipes/CatalogRowView.swift \
        ios/NorseMixology/Components/RatingStars.swift ios/NorseMixology/Components/TakeMarkers.swift \
        ios/NorseMixology.xcodeproj/project.pbxproj
git commit -m "iOS: take view model at the app root; stars and markers on cards; My ratings filter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The "My take" section on the recipe screen

**Files:**
- Create: `ios/NorseMixology/Take/StarRatingControl.swift`
- Create: `ios/NorseMixology/Take/TakeNotesEditor.swift`
- Create: `ios/NorseMixology/Take/TakePhotoStrip.swift`
- Create: `ios/NorseMixology/Take/TakePhotoViewer.swift`
- Create: `ios/NorseMixology/Take/MyTakeSection.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeDetailView.swift`
- Modify: `ios/NorseMixology.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Consumes: Task 3 `RecipeTakeViewModel` (all methods), `PhotoItem`, `AddPhotosResult`, `TakeLimits`; `RecipeDetailView`'s `recipe: Recipe`.
- Produces: `MyTakeSection(recipe:)` shown on every recipe screen (Recipes tab and Favourites share `RecipeDetailView`).

- [ ] **Step 1: `Take/StarRatingControl.swift`**

```swift
import SwiftUI

/// Five 44 pt stars. Tapping a star calls `onSelect(star)`; the view model decides
/// that tapping the current rating clears it. For VoiceOver the stars are one
/// adjustable control ("Your rating, 4 of 5": swipe up/down to change).
struct StarRatingControl: View {
    let rating: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onSelect(star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(star <= rating ? DesignTokens.accent : DesignTokens.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where rating < 5: onSelect(rating + 1)
            case .decrement where rating > 0: onSelect(rating - 1)
            default: break
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }
}
```

- [ ] **Step 2: `Take/TakeNotesEditor.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// The notes box. Saved 0.6 s after typing stops, when the screen goes away, and
/// when the app leaves the foreground — there is no Save button to forget.
struct TakeNotesEditor: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private let counterThreshold = 1_800

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What would you change? What did you serve it with?")
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 96)
                    .accessibilityLabel("Notes")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DesignTokens.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))

            if text.count >= counterThreshold {
                Text("\(text.count) of \(TakeLimits.maxNotesLength)")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityLabel("\(text.count) of \(TakeLimits.maxNotesLength) characters")
            }
        }
        .onAppear { text = take.notes(for: recipe.id) }
        .onChange(of: text) { _, newValue in
            if newValue.count > TakeLimits.maxNotesLength {
                text = String(newValue.prefix(TakeLimits.maxNotesLength))
                return
            }
            scheduleSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flush() }
        }
        .onDisappear { flush() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Saves now, unless nothing changed (loading the stored text also fires `onChange`).
    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard text != take.notes(for: recipe.id) else { return }
        take.setNotes(text, for: recipe)
    }
}
```

- [ ] **Step 3: `Take/TakePhotoViewer.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// Full-screen photo viewer: swipe between a recipe's photos, delete with confirmation.
struct TakePhotoViewer: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var isConfirmingDelete = false

    init(recipe: Recipe, startID: UUID) {
        self.recipe = recipe
        _selection = State(initialValue: startID)
    }

    var body: some View {
        // Reading the count makes the viewer refresh after a delete.
        let _ = take.photoCounts[recipe.id]
        let photos = take.photos(for: recipe.id)

        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    FullPhoto(id: photo.id)
                        .tag(photo.id)
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { isConfirmingDelete = true }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) { deleteSelected(from: photos) }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func deleteSelected(from photos: [PhotoItem]) {
        guard let position = photos.firstIndex(where: { $0.id == selection }) else { return }
        let neighbour = photos.indices.contains(position + 1) ? photos[position + 1].id
            : (position > 0 ? photos[position - 1].id : nil)
        take.removePhoto(id: selection)
        if let neighbour {
            selection = neighbour
        } else {
            dismiss()
        }
    }
}

/// One full-size photo, decoded once when it appears.
private struct FullPhoto: View {
    let id: UUID

    @Environment(RecipeTakeViewModel.self) private var take
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id) {
            image = take.fullImage(id: id).flatMap { UIImage(data: $0) }
        }
    }
}
```

- [ ] **Step 4: `Take/TakePhotoStrip.swift`**

```swift
import SwiftUI
import PhotosUI
import NorseMixologyCore

/// The photo strip: thumbnails, an "Add photo" tile (system picker, no photo-library
/// permission needed) and a viewer. Partial failures and the six-photo limit are
/// reported, never silent.
struct TakePhotoStrip: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewerTarget: ViewerTarget?
    @State private var message: AddMessage?
    @State private var isAdding = false

    private struct ViewerTarget: Identifiable {
        let id: UUID
    }

    private enum AddMessage {
        case partial(added: Int, total: Int)
        case limit
        case failed
    }

    var body: some View {
        // Reading the count makes the strip refresh after an add or delete.
        let count = take.photoCounts[recipe.id] ?? 0
        let photos = take.photos(for: recipe.id)
        let freeSlots = max(0, TakeLimits.maxPhotos - count)

        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            viewerTarget = ViewerTarget(id: photo.id)
                        } label: {
                            thumbnail(photo)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                        .accessibilityHint("Opens the photo")
                    }
                    if freeSlots > 0 {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: freeSlots, matching: .images) {
                            addTile
                        }
                        .disabled(isAdding)
                        .accessibilityLabel("Add photo")
                    }
                }
                .padding(.vertical, 2)
            }

            if freeSlots == 0 {
                Text("\(TakeLimits.maxPhotos) photos is the limit")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            if let message {
                messageText(message)
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.matchSubstituted)
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await add(items) }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            TakePhotoViewer(recipe: recipe, startID: target.id)
        }
    }

    private func thumbnail(_ photo: PhotoItem) -> some View {
        Group {
            if let image = UIImage(data: photo.thumbnail) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(DesignTokens.surfaceRaised)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))
    }

    private var addTile: some View {
        VStack(spacing: 4) {
            Image(systemName: isAdding ? "hourglass" : "plus")
                .font(.title3)
            Text("Add photo")
                .dsText(.body)
        }
        .foregroundStyle(DesignTokens.accent)
        .frame(width: 88, height: 88)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DesignTokens.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignTokens.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    @ViewBuilder
    private func messageText(_ message: AddMessage) -> some View {
        switch message {
        case .partial(let added, let total): Text("\(added) of \(total) added")
        case .limit: Text("\(TakeLimits.maxPhotos) photos is the limit")
        case .failed: Text("Couldn't add that photo")
        }
    }

    private func add(_ items: [PhotosPickerItem]) async {
        isAdding = true
        message = nil
        var datas: [Data] = []
        var unreadable = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                datas.append(data)
            } else {
                unreadable += 1
            }
        }
        pickerItems = []

        let result = await take.addPhotos(datas, for: recipe)
        let total = items.count
        let failed = result.failed + unreadable
        if result.added == total {
            message = nil
        } else if result.added > 0 {
            message = .partial(added: result.added, total: total)
        } else if result.refusedForLimit > 0 && failed == 0 {
            message = .limit
        } else {
            message = .failed
        }
        isAdding = false
    }
}
```

- [ ] **Step 5: `Take/MyTakeSection.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// "My take" on a recipe: rating, notes and photos. Shown on every recipe screen.
struct MyTakeSection: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take

    var body: some View {
        let rating = take.rating(for: recipe.id)

        VStack(alignment: .leading, spacing: 16) {
            Text("My take")
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                StarRatingControl(rating: rating) { take.setRating($0, for: recipe) }
                Text(rating == 0 ? "Not rated" : "\(rating) of 5")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityHidden(true)
            }

            TakeNotesEditor(recipe: recipe)
            TakePhotoStrip(recipe: recipe)
        }
        .alert(
            "Couldn't save your changes",
            isPresented: Binding(get: { take.lastError != nil }, set: { if !$0 { take.clearError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your changes are still on screen. Try again, and check that your device has free space.")
        }
    }
}
```

- [ ] **Step 6: Add the section to `RecipeDetailView`**

In `RecipeDetailView.swift`'s `body`, replace

```swift
                if !recipe.steps.isEmpty {
                    methodSection
                }
```

with

```swift
                if !recipe.steps.isEmpty {
                    methodSection
                }

                MyTakeSection(recipe: recipe)
```

- [ ] **Step 7: Register files and build**

```bash
cd ios && xcodegen generate && git diff --stat NorseMixology.xcodeproj
```
Expected: `project.pbxproj` changes only for the five new files.

```bash
cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tee "${TMPDIR:-/tmp}/nm-build.log" | grep -E 'error:|BUILD'
for f in StarRatingControl TakeNotesEditor TakePhotoStrip TakePhotoViewer MyTakeSection; do grep -q "SwiftCompile.*$f\.swift" "${TMPDIR:-/tmp}/nm-build.log" && echo "OK $f" || echo "MISSING $f"; done
```
Expected: `** BUILD SUCCEEDED **`, `OK` five times. If `onChange(of:) { _, newValue in ... }` or `ToolbarItemGroup(placement: .keyboard)` fails to compile, report the exact error rather than changing the design.

- [ ] **Step 8: Simulator check (controller only)**

Put test photos in the simulator's library first (a white PNG for the header contrast check in Task 7 as well):

```bash
python3 - <<'EOF'
import zlib, struct, os
def png(path, w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
d = os.environ.get('TMPDIR', '/tmp')
png(f'{d}/take-white.png', 1200, 900, (255, 255, 255))
png(f'{d}/take-lime.png', 1200, 900, (143, 227, 136))
png(f'{d}/take-dark.png', 900, 1200, (40, 50, 80))
EOF
xcrun simctl addmedia 107DA7C9-B4F6-4568-8F08-DFB149A4F204 "${TMPDIR:-/tmp}/take-white.png" "${TMPDIR:-/tmp}/take-lime.png" "${TMPDIR:-/tmp}/take-dark.png"
```

Then: open Negroni. Rate 4 stars (caption "4 of 5"); tap the 4th again (clears); rate 2 and then 5. Type a note, wait a second, leave the screen and return (note is there); relaunch the app (still there). Add three photos through the picker (the thumbnails appear; tap one; swipe to the next; Delete → confirm; the neighbour shows). Fill to six (the tile disappears and "6 photos is the limit" shows). VoiceOver labels are inspected by reading the accessibility tree. Implementers: write "SIM CHECK NOT RUN".

- [ ] **Step 9: Commit**

```bash
git add ios/NorseMixology/Take ios/NorseMixology/Recipes/RecipeDetailView.swift ios/NorseMixology.xcodeproj/project.pbxproj
git commit -m "iOS: My take section — stars, autosaved notes and a photo strip with a viewer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Header stars and the blurred-photo background

**Files:**
- Create: `ios/NorseMixology/Take/TakeHeaderBackground.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeDetailView.swift`
- Modify: `ios/NorseMixology.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Consumes: Task 3 `RecipeTakeViewModel.photos(for:)` / `photoCounts` / `ratings`; Task 5 `RatingStars`.
- Produces: `TakeHeaderBackground(thumbnail: Data?)`.

- [ ] **Step 1: `Take/TakeHeaderBackground.swift`**

```swift
import SwiftUI

/// The recipe header backdrop: the first photo, blurred and washed with the
/// screen's own background colour so title text keeps its contrast on any photo
/// (a 78% wash leaves roughly 9:1 even under a pure-white photo in dark mode).
/// Plain with no photo, or when Reduce Transparency is on.
struct TakeHeaderBackground: View {
    let thumbnail: Data?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let thumbnail, !reduceTransparency, let image = UIImage(data: thumbnail) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 24)
                .overlay(DesignTokens.background.opacity(0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped()
                .mask(
                    LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                )
                .accessibilityHidden(true)
        }
    }
}
```

- [ ] **Step 2: Use it in `RecipeDetailView`**

Add `@Environment(RecipeTakeViewModel.self) private var take` if it is not already present. In `body`, replace

```swift
                header

                if !recipe.description.isEmpty {
                    Text(recipe.description)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
```

with

```swift
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if !recipe.description.isEmpty {
                        Text(recipe.description)
                            .dsText(.body)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .background(alignment: .top) {
                    // Bleeds to the screen edges and up under the navigation bar; scrolls away with the content.
                    TakeHeaderBackground(thumbnail: headerPhoto)
                        .padding(.horizontal, -20)
                        .padding(.top, -120)
                }
```

Add this computed property beside `isFavourite`:

```swift
    /// The first photo's thumbnail. Reading `photoCounts` makes the header refresh when photos change.
    private var headerPhoto: Data? {
        _ = take.photoCounts[recipe.id]
        return take.photos(for: recipe.id).first?.thumbnail
    }
```

In the `header` view, directly after the `ViewThatFits { ... }` block (still inside the header's `VStack`), add:

```swift
            if let stars = take.ratings[recipe.id] {
                RatingStars(rating: stars, font: .subheadline)
            }
```

- [ ] **Step 3: Register files and build**

```bash
cd ios && xcodegen generate && git diff --stat NorseMixology.xcodeproj
cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tee "${TMPDIR:-/tmp}/nm-build.log" | grep -E 'error:|BUILD'
grep -q "SwiftCompile.*TakeHeaderBackground\.swift" "${TMPDIR:-/tmp}/nm-build.log" && echo "OK TakeHeaderBackground" || echo "MISSING TakeHeaderBackground"
```
Expected: `** BUILD SUCCEEDED **`, `OK TakeHeaderBackground`.

- [ ] **Step 4: Simulator check (controller only)**

Rate a recipe: the stars appear under the Build/Easy pills. Add the white PNG as its first photo: the header shows a blurred, darkened wash and the title and pills stay readable (zoom the screenshot and check). Remove the photo: the header is plain again. Settings → Accessibility → Display & Text Size → Reduce Transparency on: the header stays plain even with a photo. Dark and light appearance both. Implementers: write "SIM CHECK NOT RUN".

- [ ] **Step 5: Commit**

```bash
git add ios/NorseMixology/Take/TakeHeaderBackground.swift ios/NorseMixology/Recipes/RecipeDetailView.swift ios/NorseMixology.xcodeproj/project.pbxproj
git commit -m "iOS: your stars and a blurred first photo behind the recipe header

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Strings, docs and final verification

**Files:**
- Modify: `ios/NorseMixology/Localizable.xcstrings` (via script)
- Modify: `NORSE_MIXOLOGY_BUILD.md`

- [ ] **Step 1: Sync the String Catalog**

```bash
cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tail -1
cd ios && scripts/sync-strings.sh
grep -c -E '"(My take|Add photo|Delete this photo\?|Couldn.t save your changes|My ratings)"' NorseMixology/Localizable.xcstrings
```
Expected: `** BUILD SUCCEEDED **`, `Synced NorseMixology/Localizable.xcstrings`, then `5`. If a key is missing, report which one instead of hand-editing the catalog.

- [ ] **Step 2: Add the build-reference section**

Insert into `NORSE_MIXOLOGY_BUILD.md` directly before the `## Design System — "Modern Neon Bar"` heading:

```markdown
## Recipe take (iOS)

- **Spec:** `docs/superpowers/specs/2026-10-06-recipe-take-design.md`. Roadmap sub-project C. One "My take" per recipe; the per-time "made it" log is not built.
- **Storage:** SwiftData `RecipeTake` (rating 0…5, notes, cached `recipeName`) and `RecipePhoto` (thumbnail `Data` + `full` via `@Attribute(.externalStorage)`), both keyed by `recipeId`, added to the existing container as a lightweight migration (tested against an on-disk three-model store). Never touched by catalog updates: nothing in the take code reads the catalog, and a take survives its recipe leaving it.
- **Rules (`TakeLimits`, `RecipeTakeService`):** rating 0…5 (others rejected, not clamped); notes ≤ 2,000 chars (trimmed; whitespace-only = empty); ≤ 6 photos per recipe; a take with no rating, notes or photos is deleted; one take per recipe; every change saved immediately and a failed save throws `TakeError.saveFailed`.
- **Photos:** `PhotoProcessor` (ImageIO) downsamples while reading — a huge photo is never decoded at full size — to a ≤ 1600 px full JPEG and a ~320 px thumbnail (quality 0.8), applies EXIF orientation, never upscales, refuses unreadable data. Picked with `PhotosPicker`, so no photo-library permission. Lists and the header read thumbnails only.
- **View model:** `RecipeTakeViewModel` (`@MainActor @Observable`, app root) publishes `ratings`, `hasNotes`, `photoCounts` for cards and rows; `addPhotos` returns added / failed / refused-for-limit so nothing is dropped silently.
- **UI:** "My take" after Method on every recipe screen (shared by Recipes and Favourites): `StarRatingControl` (44 pt stars, tap the current star to clear, one adjustable VoiceOver control), `TakeNotesEditor` (autosave after 0.6 s, on disappear and when the app goes inactive), `TakePhotoStrip` + `TakePhotoViewer` (delete asks first). Header: read-only stars, and the first photo blurred under a 78% wash of the screen background (plain with no photo or Reduce Transparency). Cards and rows: read-only stars plus a quiet "Note" / "N photos" line; filter group "My ratings" (Rated, 4 stars or more).
- **Not built:** camera capture, the made-it log, searching notes, export/share (backup and iCloud is the next roadmap item — everything is in SwiftData so it can follow). BlurHash is deliberately not used for local photos; revisit if the catalog ships remote images.
```

- [ ] **Step 3: Final verification**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1`
Expected: `Executed 289 tests, with 0 failures`.

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tail -1`
Expected: `** BUILD SUCCEEDED **`.

Controller simulator pass (implementers: SIM CHECK NOT RUN): the Task 6 and 7 checks, then — cards and rows show stars and "Note" / "N photos" for the recipe you edited and nothing for others; Filters → My ratings → Rated shows only your rated recipes in both Can make and All recipes, "4 stars or more" narrows it, the chip removes it; relaunch keeps everything; largest Dynamic Type keeps the stars at 44 pt and reflows the strip; delete every thing from a recipe and confirm the take disappears from the lists.

- [ ] **Step 4: Commit**

Stage only the catalog if the sync changed it, and the docs:

```bash
git add NORSE_MIXOLOGY_BUILD.md ios/NorseMixology/Localizable.xcstrings
git commit -m "docs: recipe take build notes; sync string catalog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
