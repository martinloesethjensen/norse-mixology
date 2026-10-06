# Shopping List & Buy Next Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A shopping list of catalog ingredients (filled from recipes and a "Buy next" ranking) that lives in the Cabinet tab, where ticking an item moves it into the cabinet with undo.

**Architecture:** All data and rules live in the `NorseMixologyCore` SPM package and are unit-tested with `swift test`: a new SwiftData `@Model ShoppingItem` with `ShoppingService`, an `@Observable ShoppingListViewModel` (add / prune / tick-off / undo), and a pure `BuyNextRanking` over the `CatalogEntry` values that catalog browse (sub-project A) already computes. The app target adds a Cabinet | Shopping list segment, the Shopping list screen, an undo toast, and shopping buttons on the recipe screen. The matching engine and `CatalogAvailability` are not changed.

**Tech Stack:** Swift 5.9, SwiftUI (iOS 17), SwiftData, XCTest, xcodegen.

**Spec:** `docs/superpowers/specs/2026-10-05-shopping-list-design.md`

## Global Constraints

- Min iOS stays **17.0**; no new dependencies.
- iOS only — do not touch `android/`.
- **Additive only:** do not change `MatchingService.swift`, `CatalogAvailability.swift`, or `CatalogEntry.swift`.
- Invariant: an ingredient is never both "owned" and "to buy" for longer than one refresh, and a tick-off can never lose an item (cabinet add is saved **before** the list item is removed).
- One `ShoppingItem` per `ingredientStyleId`; every shopping-list change is saved immediately (`try? context.save()`), like favourites.
- `@Observable` view models only — no Combine, no `ObservableObject`.
- Colours and font sizes only via `DesignTokens` / `.dsText(...)` — no colour literals in views. (`.font(.title3)` on SF Symbol buttons matches the existing add-to-cabinet button.)
- Structured logging only (`AppLog`) — no `print`.
- Touch targets ≥ 44 pt; VoiceOver labels on every icon-only button; Reduce Motion respected (no row slide animation when on).
- All new UI strings end up in `ios/NorseMixology/Localizable.xcstrings` (run `ios/scripts/sync-strings.sh` after a CLI build).
- New app-target Swift files are registered by running `xcodegen generate` in `ios/`. Verify each new file appears in a `SwiftCompile` line of the build log.
- Performance: the refresh pipeline including `BuyNextRanking.rank` over 158 recipes with a 30-item cabinet stays **< 100 ms**.

**Commands used throughout:**
- Core tests: `cd ios/Packages/NorseMixologyCore && swift test` (baseline on `main`: **188 tests, 0 failures**). Filter with `swift test --filter <TestClass>`.
- App build (the `name=` destination is ambiguous on this machine — always use the id): `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build`
- Simulator checks need the iOS Simulator tool, which only the controlling session can use (and only once the user grants access). Implementer subagents write "SIM CHECK NOT RUN" for simulator steps.

**Working tree note:** `ios/NorseMixology.xcodeproj/project.pbxproj` and `ios/NorseMixology/Localizable.xcstrings` carry uncommitted Xcode edits that belong to the user (a development team ID and emoji header entries). Never stage them with `git add -A` / `git add .`; stage named files only. Where a task must commit `project.pbxproj` or `Localizable.xcstrings`, stage with `git add -p` and include only hunks this task produced.

---

## File Structure

**Core package** (`ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/`)
- Create `Models/ShoppingItem.swift` — the `@Model`.
- Create `Models/CabinetItem+Style.swift` — `CabinetItem.make(from:index:brand:date:)`, the single place a style becomes a cabinet item.
- Create `Services/ShoppingService.swift` — SwiftData access for `ShoppingItem`.
- Modify `Services/CabinetService.swift` — add `remove(id:context:)`.
- Create `ViewModels/ShoppingListViewModel.swift` — `ShoppingEntry`, `ShoppingAddResult`, `BoughtReceipt`, the view model.
- Create `Services/BuyNextRanking.swift` — `BuyNextSuggestion`, `BuyNextRanking.rank`.

**Core tests** (`ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/`)
- Create `ShoppingServiceTests.swift`, `ShoppingListViewModelTests.swift`, `BuyNextRankingTests.swift`.
- Modify `HardeningTests.swift` — add the ranking to the refresh-pipeline budget test.

**App** (`ios/NorseMixology/`)
- Modify `NorseMixologyApp.swift`, `ContentView.swift` (preview) — container + injected `ShoppingListViewModel`.
- Modify `Cabinet/CabinetViewModel.swift` — `add` uses `CabinetItem.make`.
- Modify `Cabinet/CabinetView.swift` — Cabinet | Shopping list segment.
- Create `Cabinet/ShoppingListView.swift`, `Cabinet/ShoppingItemRow.swift`, `Cabinet/BuyNextRow.swift`, `Components/UndoToast.swift`.
- Modify `Recipes/IngredientRowView.swift`, `Recipes/RecipeDetailView.swift` — shopping buttons, "Add all missing".

**Docs**
- Modify `NORSE_MIXOLOGY_BUILD.md` — "Shopping list (iOS)" section; modify the spec — amendments (Task 6).

---

### Task 1: `ShoppingItem`, `ShoppingService`, and one way to build a cabinet item

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/ShoppingItem.swift`
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/CabinetItem+Style.swift`
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/ShoppingService.swift`
- Modify: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/CabinetService.swift` (add one function)
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/ShoppingServiceTests.swift`

**Interfaces:**
- Consumes: `CabinetItem` (existing init), `IngredientStyle`, `TaxonomyIndex.familyName(for:)` / `categoryName(for:)`, `FavouriteRecipe`, `IngredientTaxonomy.loadCategories(from:)`, `CatalogFixtures.taxonomyData()` (existing test helper).
- Produces:
  - `@Model public final class ShoppingItem { id: UUID; ingredientStyleId: UUID; styleName: String; dateAdded: Date; init(id:ingredientStyleId:styleName:dateAdded:) }`
  - `CabinetItem.make(from style: IngredientStyle, index: TaxonomyIndex, brand: String? = nil, date: Date = Date()) -> CabinetItem`
  - `ShoppingService.add(styleId: UUID, styleName: String, context: ModelContext, date: Date = Date())` (no-op if listed), `remove(styleId:context:)`, `contains(styleId:context:) -> Bool`, `all(context:) -> [ShoppingItem]` (newest first)
  - `CabinetService.remove(id: UUID, context: ModelContext)`

- [ ] **Step 1: Write the failing tests**

Create `ShoppingServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter ShoppingServiceTests`
Expected: build FAILS with `cannot find type 'ShoppingItem' in scope`.

- [ ] **Step 3: Create `Models/ShoppingItem.swift`**

```swift
import Foundation
import SwiftData

/// An ingredient the user wants to buy — one per catalog `IngredientStyle`.
/// `styleName` is cached so the row still renders if a later catalog drops
/// the style (Shopping List spec §2).
@Model
public final class ShoppingItem {
    public var id: UUID
    // Defaults let SwiftData add this model to existing stores without a custom migration.
    public var ingredientStyleId: UUID = UUID()
    public var styleName: String = ""
    public var dateAdded: Date = Date()

    public init(id: UUID = UUID(), ingredientStyleId: UUID, styleName: String, dateAdded: Date = Date()) {
        self.id = id
        self.ingredientStyleId = ingredientStyleId
        self.styleName = styleName
        self.dateAdded = dateAdded
    }
}
```

- [ ] **Step 4: Create `Models/CabinetItem+Style.swift`**

```swift
import Foundation

public extension CabinetItem {
    /// A cabinet snapshot of a catalog style — the one place the cabinet's add
    /// flow and the shopping list's tick-off build cabinet items. A blank or
    /// whitespace-only brand counts as no brand.
    static func make(from style: IngredientStyle, index: TaxonomyIndex, brand: String? = nil, date: Date = Date()) -> CabinetItem {
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandValue = (trimmedBrand?.isEmpty ?? true) ? nil : trimmedBrand
        return CabinetItem(
            ingredientStyleId: style.id,
            ingredientFamilyId: style.familyId,
            categoryId: style.categoryId,
            displayName: brandValue.map { "\($0) \(style.name)" } ?? style.name,
            brand: brandValue,
            style: style.name,
            family: index.familyName(for: style),
            category: index.categoryName(for: style),
            flavorProfile: style.flavorProfile,
            dateAdded: date
        )
    }
}
```

- [ ] **Step 5: Create `Services/ShoppingService.swift`**

```swift
import Foundation
import SwiftData

/// SwiftData access layer for `ShoppingItem` — the caller owns the
/// `ModelContext`, like `CabinetService` and `FavouritesService`.
///
/// Every mutation is saved immediately: `save()` also flushes any pending
/// cabinet insert in the same context, which the tick-off ordering relies on.
public enum ShoppingService {
    /// No-op if the style is already listed, so there is never a duplicate.
    public static func add(styleId: UUID, styleName: String, context: ModelContext, date: Date = Date()) {
        guard !contains(styleId: styleId, context: context) else { return }
        context.insert(ShoppingItem(ingredientStyleId: styleId, styleName: styleName, dateAdded: date))
        persist(context)
    }

    public static func remove(styleId: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.ingredientStyleId == styleId })
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
        persist(context)
    }

    public static func contains(styleId: UUID, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.ingredientStyleId == styleId })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Most recently added first.
    public static func all(context: ModelContext) -> [ShoppingItem] {
        let descriptor = FetchDescriptor<ShoppingItem>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func persist(_ context: ModelContext) {
        // A failed explicit save leaves the change pending; SwiftData's autosave retries it.
        try? context.save()
    }
}
```

- [ ] **Step 6: Add `remove(id:)` to `Services/CabinetService.swift`**

Insert after the existing `remove(_:context:)`:

```swift
    /// Deletes the cabinet item with this id, if it still exists (used by shopping-list undo).
    public static func remove(id: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<CabinetItem>(predicate: #Predicate { $0.id == id })
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter ShoppingServiceTests`
Expected: PASS (8 tests).

If the migration test fails with a SwiftData migration error, stop and report BLOCKED with the full error — do not add a `VersionedSchema` on your own; that is a design decision.

- [ ] **Step 8: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: `Executed 196 tests, with 0 failures` (188 + 8).

- [ ] **Step 9: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/ShoppingItem.swift \
        ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/CabinetItem+Style.swift \
        ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/ShoppingService.swift \
        ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/CabinetService.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/ShoppingServiceTests.swift
git commit -m "Core: ShoppingItem model and service; CabinetItem.make builds cabinet items from a style

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `ShoppingListViewModel` — add, prune, tick off, undo

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/ViewModels/ShoppingListViewModel.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/ShoppingListViewModelTests.swift`

**Interfaces:**
- Consumes (Task 1): `ShoppingItem`, `ShoppingService.add(styleId:styleName:context:date:)` / `remove(styleId:context:)` / `all(context:)`, `CabinetItem.make(from:index:brand:date:)`, `CabinetService.remove(id:context:)`; existing `CabinetService.add(_:context:)`, `contains(styleId:context:)`, `allItems(context:)`.
- Produces (used by Tasks 4–5):
  - `public struct ShoppingEntry: Identifiable { item: ShoppingItem; style: IngredientStyle?; id: UUID }` — `style == nil` means the style left the catalog.
  - `public enum ShoppingAddResult: Equatable, Sendable { case added, alreadyListed, alreadyOwned }`
  - `public struct BoughtReceipt: Equatable, Sendable { styleId: UUID; styleName: String; createdCabinetItemId: UUID? }`
  - `@Observable public final class ShoppingListViewModel` with `init(modelContext:)`, `items: [ShoppingItem]` (newest first), `isEmpty`, `listedStyleIds: Set<UUID>`, `contains(styleId:)`, `add(_:cabinetStyleIds:) -> ShoppingAddResult`, `addAll(_:cabinetStyleIds:) -> Int`, `remove(_ item:)`, `remove(styleId:)`, `pruneOwned(cabinetStyleIds:)`, `entries(in:) -> [ShoppingEntry]`, `markBought(_:index:date:) -> BoughtReceipt?`, `undo(_:)`, `refresh()`.

- [ ] **Step 1: Write the failing tests**

Create `ShoppingListViewModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter ShoppingListViewModelTests`
Expected: build FAILS with `cannot find 'ShoppingListViewModel' in scope`.

- [ ] **Step 3: Create `ViewModels/ShoppingListViewModel.swift`**

```swift
import Foundation
import Observation
import SwiftData

/// A shopping-list item paired with its catalog style; `style` is nil when a
/// later catalog dropped it (a "ghost" — shown by cached name, not tickable).
public struct ShoppingEntry: Identifiable {
    public let item: ShoppingItem
    public let style: IngredientStyle?

    public var id: UUID { item.ingredientStyleId }
}

public enum ShoppingAddResult: Equatable, Sendable {
    case added, alreadyListed, alreadyOwned
}

/// What a tick-off did, so it can be undone exactly.
public struct BoughtReceipt: Equatable, Sendable {
    public let styleId: UUID
    public let styleName: String
    /// The cabinet item the tick created; nil when the bottle was already owned.
    public let createdCabinetItemId: UUID?
}

/// App-wide shopping-list state (Shopping List spec §2). One instance is
/// injected at the app root, like `FavouritesViewModel`, so the Cabinet tab,
/// the Shopping list screen and the recipe screen always agree.
///
/// Lives in the core package so its rules are unit-testable without a simulator.
@Observable
public final class ShoppingListViewModel {
    private let modelContext: ModelContext

    /// Most recently added first.
    public private(set) var items: [ShoppingItem] = []
    public private(set) var listedStyleIds: Set<UUID> = []

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    public var isEmpty: Bool { items.isEmpty }

    public func contains(styleId: UUID) -> Bool {
        listedStyleIds.contains(styleId)
    }

    @discardableResult
    public func add(_ style: IngredientStyle, cabinetStyleIds: Set<UUID>) -> ShoppingAddResult {
        if cabinetStyleIds.contains(style.id) { return .alreadyOwned }
        if listedStyleIds.contains(style.id) { return .alreadyListed }
        ShoppingService.add(styleId: style.id, styleName: style.name, context: modelContext)
        refresh()
        return .added
    }

    /// Adds every style that isn't owned or already listed; returns how many were added.
    @discardableResult
    public func addAll(_ styles: [IngredientStyle], cabinetStyleIds: Set<UUID>) -> Int {
        var seen = listedStyleIds.union(cabinetStyleIds)
        var added = 0
        for style in styles where !seen.contains(style.id) {
            ShoppingService.add(styleId: style.id, styleName: style.name, context: modelContext)
            seen.insert(style.id)
            added += 1
        }
        if added > 0 { refresh() }
        return added
    }

    public func remove(_ item: ShoppingItem) {
        remove(styleId: item.ingredientStyleId)
    }

    public func remove(styleId: UUID) {
        ShoppingService.remove(styleId: styleId, context: modelContext)
        refresh()
    }

    /// Drops items whose bottle is now in the cabinet, however it got there.
    public func pruneOwned(cabinetStyleIds: Set<UUID>) {
        let owned = listedStyleIds.intersection(cabinetStyleIds)
        guard !owned.isEmpty else { return }
        for styleId in owned {
            ShoppingService.remove(styleId: styleId, context: modelContext)
        }
        refresh()
    }

    /// Each item, in `items` order, with its catalog style or nil.
    public func entries(in index: TaxonomyIndex) -> [ShoppingEntry] {
        items.map { ShoppingEntry(item: $0, style: index.stylesById[$0.ingredientStyleId]) }
    }

    /// Moves the item into the cabinet, then off the list. The cabinet insert is
    /// saved first, so an interruption can only leave the bottle on both (which
    /// `pruneOwned` repairs), never on neither. Returns nil for a ghost item.
    public func markBought(_ item: ShoppingItem, index: TaxonomyIndex, date: Date = Date()) -> BoughtReceipt? {
        guard let style = index.stylesById[item.ingredientStyleId] else { return nil }

        var createdId: UUID?
        if !CabinetService.contains(styleId: style.id, context: modelContext) {
            let cabinetItem = CabinetItem.make(from: style, index: index, date: date)
            CabinetService.add(cabinetItem, context: modelContext)
            createdId = cabinetItem.id
            try? modelContext.save()
        }
        ShoppingService.remove(styleId: style.id, context: modelContext)
        refresh()
        return BoughtReceipt(styleId: style.id, styleName: style.name, createdCabinetItemId: createdId)
    }

    /// Reverses `markBought`: removes the cabinet item it created (if it still
    /// exists) and puts the item back on the list.
    public func undo(_ receipt: BoughtReceipt) {
        if let createdId = receipt.createdCabinetItemId {
            CabinetService.remove(id: createdId, context: modelContext)
        }
        // ShoppingService.add saves the context, persisting the cabinet removal too.
        ShoppingService.add(styleId: receipt.styleId, styleName: receipt.styleName, context: modelContext)
        refresh()
    }

    public func refresh() {
        items = ShoppingService.all(context: modelContext)
        listedStyleIds = Set(items.map(\.ingredientStyleId))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter ShoppingListViewModelTests`
Expected: PASS (12 tests).

- [ ] **Step 5: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: `Executed 208 tests, with 0 failures` (196 + 12).

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/ViewModels/ShoppingListViewModel.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/ShoppingListViewModelTests.swift
git commit -m "Core: ShoppingListViewModel — add, prune owned, tick off into the cabinet, undo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `BuyNextRanking` — which bottle to buy next

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/BuyNextRanking.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/BuyNextRankingTests.swift`
- Modify: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/HardeningTests.swift` (`testRefreshPipelineForA30ItemCabinetIsWellUnder100ms`, lines ~123–133)

**Interfaces:**
- Consumes: `CatalogEntry` (`recipe`, `match`, `missing`), `TasteRanking.isActive(_:)`, `TasteRanking.similarity(_:to:)`, `UserTasteProfile`, `CatalogAvailability.evaluate(recipes:cabinet:index:)` (all existing).
- Produces:
  - `public struct BuyNextSuggestion: Identifiable, Equatable, Sendable { style: IngredientStyle; readyNow: Int; movesCloser: Int; readyNowRecipeNames: [String]; id: UUID }`
  - `BuyNextRanking.rank(entries: [CatalogEntry], listedStyleIds: Set<UUID>, profile: UserTasteProfile, limit: Int = 5) -> [BuyNextSuggestion]`

- [ ] **Step 1: Write the failing tests**

Create `BuyNextRankingTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

/// Shopping List spec §2: ready-now, then moves-closer, then taste fit, then name.
final class BuyNextRankingTests: XCTestCase {
    private let zero = FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0)

    private func style(_ name: String) -> IngredientStyle {
        IngredientStyle(id: UUID(), name: name, familyId: UUID(), categoryId: UUID(), exampleBrands: [],
                        flavorProfile: zero, abvMin: 0, abvMax: 0)
    }

    private func recipe(_ name: String, sweetness: Double = 0.5, bitterness: Double = 0.5) -> Recipe {
        Recipe(id: UUID(), name: name, description: "", glassType: .rocks, method: .stir, ingredients: [], steps: [],
               flavorProfile: FlavorProfile(sweetness: sweetness, bitterness: bitterness, smokiness: 0.5, citrus: 0.5,
                                            floral: 0, spice: 0, herbal: 0.5, fruity: 0, oaky: 0, abv: 20),
               tags: [], difficulty: .easy, imageURL: nil)
    }

    private func missing(_ recipe: Recipe, _ styles: IngredientStyle...) -> CatalogEntry {
        CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: styles)
    }

    private func ready(_ recipe: Recipe) -> CatalogEntry {
        CatalogEntry(recipe: recipe, match: RecipeMatchResult(recipe: recipe, matchScore: 1, matchType: .exact, substitutions: []),
                     substitutions: [], missing: [])
    }

    private func rank(_ entries: [CatalogEntry], listed: Set<UUID> = [], profile: UserTasteProfile = .neutral,
                      limit: Int = 5) -> [BuyNextSuggestion] {
        BuyNextRanking.rank(entries: entries, listedStyleIds: listed, profile: profile, limit: limit)
    }

    private let sweetTooth = UserTasteProfile(sweetness: 1, bitterness: 0, citrus: 0.5, smokiness: 0.5, herbal: 0.5,
                                              hasCompletedOnboarding: true)

    // MARK: - Counting

    func testReadyNowCountsRecipesWhoseOnlyMissingIngredientIsTheStyle() {
        let x = style("X"), y = style("Y")
        let result = rank([missing(recipe("A"), x), missing(recipe("B"), x), missing(recipe("C"), x, y)])

        XCTAssertEqual(result.map(\.style.name), ["X", "Y"])
        XCTAssertEqual(result[0].readyNow, 2)
        XCTAssertEqual(result[0].movesCloser, 1)
        XCTAssertEqual(result[0].readyNowRecipeNames, ["A", "B"])
        XCTAssertEqual(result[1].readyNow, 0)
        XCTAssertEqual(result[1].movesCloser, 1)
    }

    func testReadyEntriesContributeNothingAndNothingMissingIsEmpty() {
        XCTAssertTrue(rank([ready(recipe("A")), ready(recipe("B"))]).isEmpty)
        XCTAssertTrue(rank([]).isEmpty)
    }

    // MARK: - Ordering

    func testReadyNowBeatsMovesCloser() {
        let x = style("X"), y = style("Y"), z = style("Z")
        // X: 1 ready now. Y: 0 ready now but 3 closer.
        let result = rank([
            missing(recipe("A"), x),
            missing(recipe("B"), y, z), missing(recipe("C"), y, z), missing(recipe("D"), y, z),
        ])
        XCTAssertEqual(result.first?.style.name, "X")
    }

    func testMovesCloserBreaksReadyNowTies() {
        let x = style("X"), y = style("Y"), z = style("Z")
        let result = rank([
            missing(recipe("A"), x),
            missing(recipe("B"), y),
            missing(recipe("C"), y, z), missing(recipe("D"), y, z),
        ])
        XCTAssertEqual(Array(result.prefix(2)).map(\.style.name), ["Y", "X"])
    }

    func testEmptyCabinetStyleShapeRanksByMovesCloser() {
        let gin = style("Gin"), lime = style("Lime"), mint = style("Mint")
        // Every recipe needs two or more bottles, as with an empty cabinet.
        let result = rank([
            missing(recipe("A"), gin, lime), missing(recipe("B"), gin, lime), missing(recipe("C"), gin, mint),
        ])
        XCTAssertEqual(result.map(\.style.name), ["Gin", "Lime", "Mint"])
        XCTAssertTrue(result.allSatisfy { $0.readyNow == 0 })
        XCTAssertEqual(result.map(\.movesCloser), [3, 2, 1])
    }

    func testIdenticalScoresSortByName() {
        let b = style("Bravo"), a = style("Alpha"), c = style("Charlie")
        let result = rank([missing(recipe("R1"), b), missing(recipe("R2"), c), missing(recipe("R3"), a)])
        XCTAssertEqual(result.map(\.style.name), ["Alpha", "Bravo", "Charlie"])
    }

    func testActiveTasteProfileBreaksTiesButNeverOverridesCounts() {
        let bitterBottle = style("Aaa Bitter"), sweetBottle = style("Zzz Sweet"), popular = style("Popular")
        let result = rank([
            missing(recipe("Bitter one", sweetness: 0, bitterness: 1), bitterBottle),
            missing(recipe("Sweet one", sweetness: 1, bitterness: 0), sweetBottle),
            missing(recipe("Bitter two", sweetness: 0, bitterness: 1), popular),
            missing(recipe("Bitter three", sweetness: 0, bitterness: 1), popular),
        ], profile: sweetTooth)

        XCTAssertEqual(result.map(\.style.name), ["Popular", "Zzz Sweet", "Aaa Bitter"])
        // Neutral profile: the tie falls back to name.
        let neutral = rank([
            missing(recipe("Bitter one", sweetness: 0, bitterness: 1), bitterBottle),
            missing(recipe("Sweet one", sweetness: 1, bitterness: 0), sweetBottle),
        ])
        XCTAssertEqual(neutral.map(\.style.name), ["Aaa Bitter", "Zzz Sweet"])
    }

    func testReadyNowRecipeNamesAreBestTasteFitFirst() {
        let x = style("X")
        let entries = [
            missing(recipe("Bitter", sweetness: 0, bitterness: 1), x),
            missing(recipe("Sweet", sweetness: 1, bitterness: 0), x),
        ]
        XCTAssertEqual(rank(entries, profile: sweetTooth).first?.readyNowRecipeNames, ["Sweet", "Bitter"])
        XCTAssertEqual(rank(entries).first?.readyNowRecipeNames, ["Bitter", "Sweet"], "neutral profile: by name")
    }

    // MARK: - Exclusions and limit

    func testListedStylesAreExcluded() {
        let x = style("X"), y = style("Y")
        let result = rank([missing(recipe("A"), x), missing(recipe("B"), y)], listed: [x.id])
        XCTAssertEqual(result.map(\.style.name), ["Y"])
    }

    func testLimitTruncatesToTheTopSuggestions() {
        let styles = (1...7).map { style("S\($0)") }
        let entries = styles.enumerated().map { offset, style in missing(recipe("R\(offset)"), style) }
        XCTAssertEqual(rank(entries).count, 5)
        XCTAssertEqual(rank(entries, limit: 2).count, 2)
        XCTAssertEqual(rank(entries, limit: 0).count, 0)
    }

    // MARK: - Real catalog

    private func catalog() throws -> (index: TaxonomyIndex, recipes: [Recipe]) {
        let index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        return (index, try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData()))
    }

    private func cabinet(_ names: [String], index: TaxonomyIndex) throws -> [CabinetItem] {
        try names.map { name in
            CabinetItem.make(from: try XCTUnwrap(index.stylesById.values.first { $0.name == name }), index: index)
        }
    }

    func testLastWordCabinetSuggestsGreenChartreuseAsReadyNow() throws {
        let (index, recipes) = try catalog()
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet(["London Dry Gin", "Lime Juice", "Raspberry Liqueur"], index: index), index: index)

        let chartreuse = try XCTUnwrap(rank(entries, limit: 100).first { $0.style.name == "Green Chartreuse" })
        XCTAssertGreaterThanOrEqual(chartreuse.readyNow, 1)
        XCTAssertTrue(chartreuse.readyNowRecipeNames.contains("Last Word"))
    }

    func testEmptyCabinetStillSuggestsInRankOrder() throws {
        let (index, recipes) = try catalog()
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)

        let result = rank(entries)
        XCTAssertEqual(result.count, 5)
        for (lhs, rhs) in zip(result, result.dropFirst()) {
            XCTAssertTrue(lhs.readyNow > rhs.readyNow || (lhs.readyNow == rhs.readyNow && lhs.movesCloser >= rhs.movesCloser),
                          "\(lhs.style.name) ranked above \(rhs.style.name)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter BuyNextRankingTests`
Expected: build FAILS with `cannot find 'BuyNextRanking' in scope`.

- [ ] **Step 3: Create `Services/BuyNextRanking.swift`**

```swift
import Foundation

/// One "buy next" bottle and what it would do for the user.
public struct BuyNextSuggestion: Identifiable, Equatable, Sendable {
    public let style: IngredientStyle
    /// Recipes whose ONLY missing ingredient is this style — Ready the moment it's owned.
    public let readyNow: Int
    /// Recipes missing this style plus at least one other.
    public let movesCloser: Int
    /// The ready-now recipes, best taste fit first (by name for a neutral profile).
    public let readyNowRecipeNames: [String]

    public var id: UUID { style.id }
}

/// Ranks the bottles that would unlock the most recipes (Shopping List spec §2).
/// Reads `CatalogEntry.missing` only — never re-runs the matching engine.
public enum BuyNextRanking {
    public static func rank(
        entries: [CatalogEntry],
        listedStyleIds: Set<UUID>,
        profile: UserTasteProfile,
        limit: Int = 5
    ) -> [BuyNextSuggestion] {
        struct Tally {
            let style: IngredientStyle
            var readyNow: [(name: String, fit: Double)] = []
            var movesCloser = 0
            var fit = 0.0
        }

        let tasteIsActive = TasteRanking.isActive(profile)
        var tallies: [UUID: Tally] = [:]
        for entry in entries where entry.match == nil && !entry.missing.isEmpty {
            let fit = tasteIsActive ? TasteRanking.similarity(profile, to: entry.recipe.flavorProfile) : 0
            for style in entry.missing where !listedStyleIds.contains(style.id) {
                var tally = tallies[style.id] ?? Tally(style: style)
                if entry.missing.count == 1 {
                    tally.readyNow.append((entry.recipe.name, fit))
                } else {
                    tally.movesCloser += 1
                }
                tally.fit += fit
                tallies[style.id] = tally
            }
        }

        let ranked = tallies.values.sorted { lhs, rhs in
            if lhs.readyNow.count != rhs.readyNow.count { return lhs.readyNow.count > rhs.readyNow.count }
            if lhs.movesCloser != rhs.movesCloser { return lhs.movesCloser > rhs.movesCloser }
            if lhs.fit != rhs.fit { return lhs.fit > rhs.fit }
            let byName = lhs.style.name.localizedStandardCompare(rhs.style.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.style.id.uuidString < rhs.style.id.uuidString // deterministic for duplicate names
        }

        return ranked.prefix(max(limit, 0)).map { tally in
            let names = tally.readyNow
                .sorted { lhs, rhs in
                    lhs.fit != rhs.fit ? lhs.fit > rhs.fit : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                .map(\.name)
            return BuyNextSuggestion(style: tally.style, readyNow: tally.readyNow.count,
                                     movesCloser: tally.movesCloser, readyNowRecipeNames: names)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter BuyNextRankingTests`
Expected: PASS (12 tests).

- [ ] **Step 5: Add the ranking to the budget test**

In `HardeningTests.swift`, `testRefreshPipelineForA30ItemCabinetIsWellUnder100ms`, add one line inside the timed region, directly after `_ = RecipeFilterOptions(recipes: recipes, index: index)`:

```swift
        let suggestions = BuyNextRanking.rank(entries: entries, listedStyleIds: [], profile: profile)
```

and one assertion after `XCTAssertFalse(filtered.isEmpty)`:

```swift
        XCTAssertFalse(suggestions.isEmpty)
```

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter HardeningTests`
Expected: PASS.

- [ ] **Step 6: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: `Executed 220 tests, with 0 failures` (208 + 12).

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/BuyNextRanking.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/BuyNextRankingTests.swift \
        ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/HardeningTests.swift
git commit -m "Core: BuyNextRanking — bottles that unlock the most recipes; covered by the budget test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Cabinet tab — Shopping list screen, tick-off and undo

**Files:**
- Modify: `ios/NorseMixology/NorseMixologyApp.swift` (container + view model + `.environment`)
- Modify: `ios/NorseMixology/ContentView.swift` (preview only)
- Modify: `ios/NorseMixology/Cabinet/CabinetViewModel.swift` (`add` uses `CabinetItem.make`)
- Modify: `ios/NorseMixology/Cabinet/CabinetView.swift` (segment)
- Create: `ios/NorseMixology/Cabinet/ShoppingListView.swift`
- Create: `ios/NorseMixology/Cabinet/ShoppingItemRow.swift`
- Create: `ios/NorseMixology/Cabinet/BuyNextRow.swift`
- Create: `ios/NorseMixology/Components/UndoToast.swift`
- Modify: `ios/NorseMixology.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Consumes: Task 1 `ShoppingItem`, `CabinetItem.make`; Task 2 `ShoppingListViewModel`, `ShoppingEntry`, `BoughtReceipt`; Task 3 `BuyNextRanking`, `BuyNextSuggestion`; existing `RecipeBrowserViewModel.entries` / `refresh(cabinet:taxonomyStore:)`, `CabinetViewModel.items` / `refresh()`, `TaxonomyStore.index`, `TasteProfileStore.load()`.
- Produces: `ShoppingListViewModel` in the environment for every view (used by Task 5); `UndoToast(message:onUndo:onDismiss:)`.

- [ ] **Step 1: Container and environment in `NorseMixologyApp.swift`**

Add a stored property after `cabinetViewModel`:

```swift
    @State private var shoppingListViewModel: ShoppingListViewModel
```

Change the container line to:

```swift
            let container = try ModelContainer(for: CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self)
```

After `_cabinetViewModel = ...` add:

```swift
            _shoppingListViewModel = State(initialValue: ShoppingListViewModel(modelContext: container.mainContext))
```

After `.environment(cabinetViewModel)` add:

```swift
                .environment(shoppingListViewModel)
```

Update the comment above the container to: `// so the app-wide Favourites, Cabinet and ShoppingList view models can share its main context.`

- [ ] **Step 2: Preview in `ContentView.swift`**

In `#Preview`, change `for: CabinetItem.self, FavouriteRecipe.self,` to `for: CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self,` and after `.environment(CabinetViewModel(modelContext: container.mainContext))` add:

```swift
            .environment(ShoppingListViewModel(modelContext: container.mainContext))
```

- [ ] **Step 3: `CabinetViewModel.add` uses the shared builder**

Replace the body of `add(_:taxonomyStore:brand:)` from `let trimmedBrand = ...` through the closing `)` of the `CabinetItem(...)` initialiser with:

```swift
        let item = CabinetItem.make(from: style, index: taxonomyStore.index, brand: brand)
```

Keep the `guard !contains(...)` line before it and the `CabinetService.add(...)` + animated `refresh()` after it unchanged.

- [ ] **Step 4: Create `Components/UndoToast.swift`**

```swift
import SwiftUI

/// A bottom toast with an Undo action. The host decides when it disappears
/// (a timer, or only on Undo/Dismiss while VoiceOver is running).
struct UndoToast: View {
    let message: Text
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            message
                .dsText(.body)
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo", action: onUndo)
                .dsText(.heading)
                .foregroundStyle(DesignTokens.accent)
                .frame(minWidth: 44, minHeight: 44)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DesignTokens.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 5: Create `Cabinet/BuyNextRow.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// One "buy next" bottle: what it unlocks, and a button to put it on the list.
struct BuyNextRow: View {
    let suggestion: BuyNextSuggestion
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.style.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                subtitle
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Image(systemName: "cart.badge.plus")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add \(suggestion.style.name) to shopping list"))
        }
    }

    /// "+3 ready now · Last Word, Alaska, +1" or "Gets 24 recipes closer".
    private var subtitle: Text {
        guard suggestion.readyNow > 0 else {
            return Text("Gets \(suggestion.movesCloser) recipes closer")
        }
        let shown = suggestion.readyNowRecipeNames.prefix(2).joined(separator: ", ")
        let more = suggestion.readyNowRecipeNames.count - 2
        return more > 0
            ? Text("+\(suggestion.readyNow) ready now · \(shown), +\(more)")
            : Text("+\(suggestion.readyNow) ready now · \(shown)")
    }
}
```

- [ ] **Step 6: Create `Cabinet/ShoppingItemRow.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// One shopping-list item. The leading circle marks it bought (moves it to the
/// cabinet). A ghost item — its style left the catalog — can't be ticked.
struct ShoppingItemRow: View {
    let entry: ShoppingEntry
    let familyName: String
    let onBought: () -> Void

    private var isGhost: Bool { entry.style == nil }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onBought) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(isGhost ? DesignTokens.matchUnavailable : DesignTokens.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGhost)
            .accessibilityLabel(Text("Bought \(entry.item.styleName), move to cabinet"))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.item.styleName)
                    .dsText(.heading)
                    .foregroundStyle(isGhost ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                if isGhost {
                    Text("No longer in the catalog")
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                } else {
                    Text(verbatim: familyName)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}
```

- [ ] **Step 7: Create `Cabinet/ShoppingListView.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// The Shopping list segment of the Cabinet tab: "Buy next" suggestions and the
/// user's list. Ticking an item moves it into the cabinet, with an undo toast.
struct ShoppingListView: View {
    @Environment(ShoppingListViewModel.self) private var shopping
    @Environment(CabinetViewModel.self) private var cabinet
    @Environment(RecipeBrowserViewModel.self) private var browser
    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var profile = UserTasteProfile.neutral
    @State private var lastReceipt: BoughtReceipt?
    @State private var boughtCount = 0
    @State private var toastTimer: Task<Void, Never>?

    private var cabinetStyleIds: Set<UUID> { Set(cabinet.items.map(\.ingredientStyleId)) }

    var body: some View {
        let index = taxonomyStore.index
        let entries = shopping.entries(in: index)
        let suggestions = BuyNextRanking.rank(entries: browser.entries, listedStyleIds: shopping.listedStyleIds, profile: profile)

        Group {
            if entries.isEmpty && suggestions.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to buy", systemImage: "cart")
                } description: {
                    Text("Your cabinet covers every recipe.")
                }
                .dsScreenBackground()
            } else {
                List {
                    if !suggestions.isEmpty {
                        Section {
                            ForEach(suggestions) { suggestion in
                                BuyNextRow(suggestion: suggestion) {
                                    shopping.add(suggestion.style, cabinetStyleIds: cabinetStyleIds)
                                }
                                .listRowBackground(DesignTokens.surface)
                            }
                        } header: {
                            sectionHeader(Text("Buy next"))
                        }
                    }
                    if !entries.isEmpty {
                        Section {
                            ForEach(entries) { entry in
                                ShoppingItemRow(
                                    entry: entry,
                                    familyName: entry.style.map { index.familyName(for: $0) } ?? "",
                                    onBought: { markBought(entry.item) }
                                )
                                .listRowBackground(DesignTokens.surface)
                                .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
                            }
                            .onDelete { offsets in
                                for offset in offsets {
                                    shopping.remove(entries[offset].item)
                                }
                            }
                        } header: {
                            sectionHeader(Text("Your list (\(entries.count))"))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .dsListBackground()
            }
        }
        .overlay(alignment: .bottom) {
            if let receipt = lastReceipt {
                UndoToast(
                    message: Text("Moved \(receipt.styleName) to your cabinet"),
                    onUndo: { undo(receipt) },
                    onDismiss: { dismissToast() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.success, trigger: boughtCount)
        .onAppear {
            profile = TasteProfileStore.load()
            shopping.pruneOwned(cabinetStyleIds: cabinetStyleIds)
            // Suggestions must reflect the cabinet as it is now, not as the Recipes tab last saw it.
            browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)
        }
        .onDisappear { dismissToast() }
    }

    private func sectionHeader(_ title: Text) -> some View {
        title
            .dsText(.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(DesignTokens.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func markBought(_ item: ShoppingItem) {
        var receipt: BoughtReceipt?
        withAnimation(reduceMotion ? nil : .default) {
            receipt = shopping.markBought(item, index: taxonomyStore.index)
        }
        guard let receipt else { return }
        cabinet.refresh()
        browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)
        boughtCount += 1
        AccessibilityNotification.Announcement(String(localized: "Moved \(receipt.styleName) to your cabinet")).post()
        showToast(for: receipt)
    }

    private func undo(_ receipt: BoughtReceipt) {
        shopping.undo(receipt)
        cabinet.refresh()
        browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)
        dismissToast()
    }

    /// 8 s, or until Undo/Dismiss while VoiceOver is running. A new tick replaces the toast.
    private func showToast(for receipt: BoughtReceipt) {
        toastTimer?.cancel()
        lastReceipt = receipt
        guard !voiceOverEnabled else { return }
        toastTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            lastReceipt = nil
        }
    }

    private func dismissToast() {
        toastTimer?.cancel()
        toastTimer = nil
        lastReceipt = nil
    }
}
```

- [ ] **Step 8: Segment in `CabinetView.swift`**

Add below the existing `@State private var isPresentingAddSheet = false`:

```swift
    @Environment(ShoppingListViewModel.self) private var shopping
    /// Remembered across launches.
    @SceneStorage("cabinet.segment") private var segmentRaw = CabinetSegment.cabinet.rawValue

    private enum CabinetSegment: String {
        case cabinet, shopping
    }

    private var segment: Binding<CabinetSegment> {
        Binding(
            get: { CabinetSegment(rawValue: segmentRaw) ?? .cabinet },
            set: { segmentRaw = $0.rawValue }
        )
    }
```

Replace the whole `NavigationStack { ... }` block in `body` (from `NavigationStack {` to its closing `}` before `.onAppear`) with:

```swift
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: segment) {
                    Text("Cabinet").tag(CabinetSegment.cabinet)
                    Text("Shopping list (\(shopping.items.count))").tag(CabinetSegment.shopping)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch segment.wrappedValue {
                case .cabinet:
                    content(viewModel: viewModel)
                case .shopping:
                    ShoppingListView()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .dsScreenBackground()
            .navigationTitle("Cabinet")
            .toolbar {
                if segment.wrappedValue == .cabinet {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isPresentingAddSheet = true
                        } label: {
                            Label("Add Ingredient", systemImage: "plus")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
```

Replace `.onAppear { viewModel.refresh() }` with:

```swift
        .onAppear {
            viewModel.refresh()
            // Keeps the segment's count honest if a bottle reached the cabinet another way.
            shopping.pruneOwned(cabinetStyleIds: Set(viewModel.items.map(\.ingredientStyleId)))
        }
```

- [ ] **Step 9: Register files and build**

Run:
```bash
cd ios && xcodegen generate && git diff --stat NorseMixology.xcodeproj
```
Expected: `project.pbxproj` changes (four new file entries plus ID churn on `FloatingIcon.swift`, plus the user's pre-existing uncommitted edits).

Run:
```bash
cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tee "${TMPDIR:-/tmp}/nm-build.log" | grep -E 'error:|BUILD'
for f in ShoppingListView ShoppingItemRow BuyNextRow UndoToast; do grep -q "SwiftCompile.*$f\.swift" "${TMPDIR:-/tmp}/nm-build.log" && echo "OK $f" || echo "MISSING $f"; done
```
Expected: `** BUILD SUCCEEDED **` and `OK` for all four.

- [ ] **Step 10: Simulator check (controller only)**

With London Dry Gin + Lime Juice + Raspberry Liqueur in the cabinet: Cabinet tab → Shopping list. Buy next shows Green Chartreuse "+N ready now · Last Word…"; tap its cart → it appears under Your list (1) and leaves Buy next; tick it → success haptic, row leaves, toast "Moved Green Chartreuse to your cabinet"; Undo → back on the list and gone from the cabinet; tick again and wait 8 s → toast disappears, Cabinet segment lists Green Chartreuse. Relaunch → the segment is remembered. Implementers: write "SIM CHECK NOT RUN".

- [ ] **Step 11: Commit**

Stage named files only; for `project.pbxproj` use `git add -p` and take only hunks for the four new files and the `FloatingIcon.swift` ID churn (never the `DEVELOPMENT_TEAM` or product-reference hunks, which are the user's).

```bash
git add ios/NorseMixology/NorseMixologyApp.swift ios/NorseMixology/ContentView.swift \
        ios/NorseMixology/Cabinet/CabinetViewModel.swift ios/NorseMixology/Cabinet/CabinetView.swift \
        ios/NorseMixology/Cabinet/ShoppingListView.swift ios/NorseMixology/Cabinet/ShoppingItemRow.swift \
        ios/NorseMixology/Cabinet/BuyNextRow.swift ios/NorseMixology/Components/UndoToast.swift
git add -p ios/NorseMixology.xcodeproj/project.pbxproj
git commit -m "iOS: Shopping list in the Cabinet tab — buy next, tick off into the cabinet, undo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Recipe screen — add to shopping list

**Files:**
- Modify: `ios/NorseMixology/Recipes/IngredientRowView.swift` (properties + `body` + new `actionButtons`)
- Modify: `ios/NorseMixology/Recipes/RecipeDetailView.swift` (environment, `ingredientsSection`, add-to-cabinet callback)

**Interfaces:**
- Consumes: Task 2 `ShoppingListViewModel.contains(styleId:)` / `add(_:cabinetStyleIds:)` / `addAll(_:cabinetStyleIds:)` / `remove(styleId:)` / `pruneOwned(cabinetStyleIds:)`; environment injection from Task 4.
- Produces: `IngredientRowView(..., onAdd:, onAddToList:, isListed:)`.

- [ ] **Step 1: Buttons in `IngredientRowView`**

Add below `var onAdd: (() -> Void)? = nil`:

```swift
    /// Set only for a missing *required* ingredient: toggles it on the shopping list.
    var onAddToList: (() -> Void)? = nil
    var isListed = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
```

Replace the whole `} else if let onAdd { ... }` branch in `body` with:

```swift
        } else if onAdd != nil || onAddToList != nil {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: keep the name readable and put the buttons underneath.
                VStack(alignment: .leading, spacing: 4) {
                    rowContent(substitute: nil)
                    HStack(spacing: 4) { actionButtons }
                        .padding(.leading, iconWidth + 12)
                }
            } else {
                HStack(alignment: .top, spacing: 4) {
                    rowContent(substitute: nil)
                    actionButtons
                }
            }
```

(the existing `} else { rowContent(substitute: nil) }` stays after it).

Add this property below `body`:

```swift
    @ViewBuilder
    private var actionButtons: some View {
        if let onAdd {
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add \(name) to cabinet"))
        }
        if let onAddToList {
            Button(action: onAddToList) {
                Image(systemName: isListed ? "cart.fill" : "cart.badge.plus")
                    .font(.title3)
                    .foregroundStyle(isListed ? DesignTokens.accent : DesignTokens.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isListed ? Text("Remove \(name) from shopping list") : Text("Add \(name) to shopping list"))
        }
    }
```

- [ ] **Step 2: Wire the recipe screen in `RecipeDetailView`**

Add to the environment properties:

```swift
    @Environment(ShoppingListViewModel.self) private var shopping
```

Add these helpers below `private var isFavourite`:

```swift
    /// Missing required styles in recipe order, without duplicates.
    private var missingStyles: [IngredientStyle] {
        var seen: Set<UUID> = []
        return recipe.ingredients.compactMap { ingredient -> IngredientStyle? in
            guard missingStyleIds.contains(ingredient.ingredientStyleId),
                  seen.insert(ingredient.ingredientStyleId).inserted else { return nil }
            return taxonomyStore.stylesById[ingredient.ingredientStyleId]
        }
    }

    private func toggleListed(_ style: IngredientStyle) {
        if shopping.contains(styleId: style.id) {
            shopping.remove(styleId: style.id)
        } else {
            shopping.add(style, cabinetStyleIds: cabinetStyleIds)
        }
    }
```

In `ingredientsSection`, change the `IngredientRowView(...)` call so it also passes the shopping arguments:

```swift
                    IngredientRowView(
                        name: style?.name ?? "Unknown ingredient",
                        ingredient: row.ingredient,
                        status: row.status,
                        substitute: row.substitution,
                        onAdd: canAdd ? { addingStyle = style } : nil,
                        onAddToList: canAdd ? { if let style { toggleListed(style) } } : nil,
                        isListed: style.map { shopping.contains(styleId: $0.id) } ?? false
                    )
```

Directly after `sectionHeading("Ingredients")` in `ingredientsSection`, add:

```swift
            if missingStyles.count >= 2 {
                let unlisted = missingStyles.filter { !shopping.contains(styleId: $0.id) }
                Button {
                    shopping.addAll(unlisted, cabinetStyleIds: cabinetStyleIds)
                } label: {
                    Label("Add all missing to shopping list (\(missingStyles.count))", systemImage: "cart.badge.plus")
                        .dsText(.body)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(DesignTokens.accent)
                .disabled(unlisted.isEmpty)
            }
```

In the existing add-to-cabinet sheet callback (`AddIngredientConfirmationView(...) { ... }`), add after `browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)`:

```swift
                shopping.pruneOwned(cabinetStyleIds: Set(cabinet.items.map(\.ingredientStyleId)))
```

- [ ] **Step 3: Build**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Simulator check (controller only)**

Cabinet: London Dry Gin only. Recipes → All recipes → Negroni (missing Sweet/Rosso Vermouth and Bitter Aperitif): both rows show ⊕ and a cart; "Add all missing to shopping list (2)" adds both and becomes disabled; carts turn filled; tap a filled cart → removed, button re-enabled. Add Bitter Aperitif to the cabinet with ⊕ → it leaves the shopping list (Cabinet → Shopping list count drops). Orange-wheel garnish row has neither button. At the largest accessibility text size the buttons sit below the ingredient name. Favourites → any unmakeable favourite shows no shopping buttons. Implementers: write "SIM CHECK NOT RUN".

- [ ] **Step 5: Commit**

```bash
git add ios/NorseMixology/Recipes/IngredientRowView.swift ios/NorseMixology/Recipes/RecipeDetailView.swift
git commit -m "iOS: add missing ingredients to the shopping list from the recipe screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Strings, docs, final verification

**Files:**
- Modify: `ios/NorseMixology/Localizable.xcstrings` (via script)
- Modify: `NORSE_MIXOLOGY_BUILD.md` (new section before `## Design System — "Modern Neon Bar"`)
- Modify: `docs/superpowers/specs/2026-10-05-shopping-list-design.md` (amendments)

- [ ] **Step 1: Sync the String Catalog**

Build first so fresh `.stringsdata` exist (default DerivedData, no `-derivedDataPath`), then sync:

```bash
cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tail -1
cd ios && scripts/sync-strings.sh
grep -c -E '"(Buy next|Nothing to buy|Add %@ to shopping list|Moved %@ to your cabinet)"' NorseMixology/Localizable.xcstrings
```
Expected: `** BUILD SUCCEEDED **`, `Synced NorseMixology/Localizable.xcstrings`, then `4`.

- [ ] **Step 2: Add the build-reference section**

Insert into `NORSE_MIXOLOGY_BUILD.md`, directly before `## Design System — "Modern Neon Bar"`:

```markdown
## Shopping list (iOS)

- **Spec:** `docs/superpowers/specs/2026-10-05-shopping-list-design.md`. Roadmap sub-project B.
- **Storage:** SwiftData `ShoppingItem` (one per `ingredientStyleId`, cached `styleName`) in the same container as `CabinetItem`/`FavouriteRecipe`; added as a lightweight migration (tested against an on-disk two-model store). Every change saved immediately.
- **Rules live in core:** `ShoppingListViewModel` (injected at the app root) — `add` refuses owned or listed styles, `addAll` counts what it added, `pruneOwned` drops listed styles now in the cabinet (run on Cabinet/Shopping appear and after a recipe-screen add).
- **Tick-off ordering:** `markBought` saves the cabinet insert *before* removing the list item, so an interruption leaves the bottle on both (repaired by `pruneOwned`), never on neither. `BoughtReceipt.createdCabinetItemId` makes undo remove only the cabinet item the tick created. Ghost items (style left the catalog) can't be ticked but can be deleted.
- **One way to build a cabinet item:** `CabinetItem.make(from:index:brand:date:)` — used by `CabinetViewModel.add` and by tick-off.
- **Buy next (`BuyNextRanking`)** reads `CatalogEntry.missing` only: ready-now count, then moves-closer count, then summed taste fit (only for an active profile), then name. Listed styles excluded; top 5. Covered by the refresh-pipeline budget test (< 100 ms).
- **UI:** Cabinet tab segment `Cabinet | Shopping list (N)` (`@SceneStorage("cabinet.segment")`). Undo toast for 8 s, or until Undo/Dismiss while VoiceOver runs. Recipe screen: cart button beside ⊕ on missing required ingredients, and "Add all missing" for ≥ 2.
- **Android parity:** not ported (Android paused).
```

- [ ] **Step 3: Amend the spec to match what was built**

In `docs/superpowers/specs/2026-10-05-shopping-list-design.md`:
- §2 `ShoppingService`: replace `static func add(style:, date:, context:)` with `static func add(styleId:, styleName:, context:, date:)` (undo re-adds from a receipt, which has no `IngredientStyle`); add `CabinetService.remove(id:context:)` and `CabinetItem.make(from:index:brand:date:)`.
- §2 view model: add `listedStyleIds`, `markBought(_:index:date:) -> BoughtReceipt?` and `undo(_:)` with `BoughtReceipt { styleId, styleName, createdCabinetItemId }`, noting tick-off/undo live in core (not the app layer) so they are unit-tested.
- §3 Shopping list screen: the checkbox is `circle` only (the row leaves on tick, so there is no filled state); the toast has a Dismiss (✕) button, which is how VoiceOver users close it; ticking also posts a VoiceOver announcement.
- Set **Status:** to `Implemented 2026-10-06`.

- [ ] **Step 4: Final verification**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: `Executed 220 tests, with 0 failures`.

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'id=107DA7C9-B4F6-4568-8F08-DFB149A4F204' build 2>&1 | tail -1`
Expected: `** BUILD SUCCEEDED **`

Simulator (controller only): Reduce Motion on → ticking does not slide; largest Dynamic Type → recipe-screen buttons sit below names, Buy next rows don't truncate; VoiceOver → tick announces, toast stays until Undo/Dismiss.

- [ ] **Step 5: Commit**

`Localizable.xcstrings` also carries the user's pre-existing uncommitted emoji-header edits: stage it with `git add -p` and take only hunks for strings this feature added.

```bash
git add -p ios/NorseMixology/Localizable.xcstrings
git add NORSE_MIXOLOGY_BUILD.md docs/superpowers/specs/2026-10-05-shopping-list-design.md
git commit -m "docs: shopping list build notes; sync string catalog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
