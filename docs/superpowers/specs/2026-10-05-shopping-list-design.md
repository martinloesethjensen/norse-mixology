# Shopping List & "What to Buy Next" — Design

**Date:** 2026-10-05
**Status:** Implemented 2026-10-06
**Scope:** iOS only (Android paused). Sub-project **B** of the post-MVP roadmap (see `2026-10-04-recipe-catalog-browse-design.md` §7). Builds on **A** (catalog browse), which is merged.

---

## 1. Goal and decisions

Let the user keep a **shopping list** of ingredients to buy, fill it from recipes in one tap, tick items off to move them into the cabinet, and see **what to buy next**: the bottles that unlock the most recipes.

Guiding principle: **failure first, additive only.** The matching engine and `CatalogAvailability` are not changed; this feature only reads `CatalogEntry`. Invariant: *an ingredient is never both "owned" and "to buy" for longer than one refresh, and a tick-off can never lose an item.*

| Decision | Choice | Why |
|---|---|---|
| Placement | **Cabinet \| Shopping list** segmented control inside the Cabinet tab | No fifth tab; ticking moves items one screen over |
| Item type | **Catalog ingredient style only** (cached name for display) | Ticking can move it into the cabinet; no free-text rows to special-case. Free text/custom ingredients belong to D |
| Storage | New SwiftData `@Model ShoppingItem` in the existing store; service + view model in `NorseMixologyCore` (same shape as Favourites) | Consistent, unit-testable without a simulator; adding a model is a lightweight migration |
| Ranking | "Ready now", then "moves closer", then taste fit, then name | Explainable numbers; still useful for an empty cabinet |
| Tick-off | Add to cabinet **first**, then remove from list; undo toast | A crash between steps leaves the item on both (pruned on next refresh), never on neither |
| Manual add | **Out of scope** — list is fed from recipes and Buy next | Keeps the spec small; picker reuse comes with D |

Rejected: marking shopping items as "wanted" `CabinetItem`s (the engine reads every `CabinetItem`, so unowned bottles would make recipes falsely Ready); a UserDefaults JSON blob (inconsistent with cabinet/favourites storage, harder to query and test).

---

## 2. Core logic (`NorseMixologyCore`)

### Model and service

```swift
@Model public final class ShoppingItem {
    public var id: UUID
    public var ingredientStyleId: UUID = UUID()
    public var styleName: String = ""        // cached; shown if the style leaves the catalog
    public var dateAdded: Date = Date()
}

public enum ShoppingService {            // thin SwiftData access, like FavouritesService
    static func all(context:) -> [ShoppingItem]          // newest first
    static func contains(styleId:, context:) -> Bool
    static func add(styleId:, styleName:, context:, date:)   // takes id+name, not IngredientStyle: undo re-adds from a receipt
    static func remove(styleId:, context:)
}

// Also added: CabinetService.remove(id:context:) and
// CabinetItem.make(from:index:brand:date:) (the single way to build a cabinet item;
// used by CabinetViewModel.add and by tick-off).
```

One item per `ingredientStyleId`. Every change is saved immediately (as favourites are).

### `ShoppingListViewModel` (`@Observable`, injected at the app root)

```swift
public enum ShoppingAddResult { case added, alreadyListed, alreadyOwned }

public final class ShoppingListViewModel {
    public private(set) var items: [ShoppingItem]
    public init(modelContext: ModelContext)
    public func contains(styleId: UUID) -> Bool
    @discardableResult
    public func add(_ style: IngredientStyle, cabinetStyleIds: Set<UUID>) -> ShoppingAddResult
    public func addAll(_ styles: [IngredientStyle], cabinetStyleIds: Set<UUID>) -> Int   // number actually added
    public func remove(_ item: ShoppingItem)
    public func remove(styleId: UUID)
    public func pruneOwned(cabinetStyleIds: Set<UUID>)       // drops items now in the cabinet
    public var listedStyleIds: Set<UUID> { get }
    public func markBought(_ item: ShoppingItem, index: TaxonomyIndex, date: Date) -> BoughtReceipt?
    public func undo(_ receipt: BoughtReceipt)   // saves the cabinet removal itself (explicit save), so it persists even if the item was already re-added to the list
    public func entries(in index: TaxonomyIndex) -> [ShoppingEntry]   // ShoppingEntry { item, style? } — style nil = left the catalog
    public func refresh()
}

public struct BoughtReceipt { let styleId: UUID; let styleName: String; let createdCabinetItemId: UUID? }
```

Tick-off (`markBought`) and `undo` live in core, not the app layer, so they are unit-tested.

### `BuyNextRanking`

```swift
public struct BuyNextSuggestion: Identifiable, Equatable, Sendable {
    public let style: IngredientStyle
    public let readyNow: Int              // recipes whose ONLY missing ingredient is this style
    public let movesCloser: Int           // recipes missing this style plus at least one other
    public let readyNowRecipeNames: [String]   // for the row subtitle, best taste fit first
    public var id: UUID { style.id }
}

public enum BuyNextRanking {
    public static func rank(entries: [CatalogEntry], listedStyleIds: Set<UUID>,
                            profile: UserTasteProfile, limit: Int = 5) -> [BuyNextSuggestion]
}
```

- Source: `CatalogEntry.missing` (from A). Only entries with `missing` non-empty count; `.ready` entries contribute nothing.
- Sort: `readyNow` desc, then `movesCloser` desc, then taste fit desc (sum of `TasteRanking.similarity` over the recipes the style appears in; 0 when `TasteRanking.isActive` is false), then name ascending (deterministic).
- Styles already on the list are excluded. Result is truncated to `limit`.
- A style that is missing for one recipe may be substituted for another; only the recipes where it is in `missing` count.

### Tick-off and undo (in core: `ShoppingListViewModel`)

1. `markBought` builds the cabinet item with `CabinetItem.make`, inserts it and saves. It skips the insert if the bottle is already owned, and records `createdCabinetItemId`.
2. It removes the list item, which saves.
3. The app then refreshes `CabinetViewModel` and the browser view model.

Undo removes only the cabinet item the tick created (`createdCabinetItemId`), if it still exists, and saves explicitly. It then re-adds the list item (a no-op if it was already re-added). Ghost items: `markBought` returns nil.

---

## 3. App (`ios/NorseMixology`)

### Cabinet tab — `CabinetView`

- A segmented `Picker` (Cabinet | Shopping list (N)) under the title, `@SceneStorage("cabinet.segment")`. The Cabinet segment is the existing screen, unchanged. The toolbar "+" (add ingredient to cabinet) shows only on the Cabinet segment.
- `CabinetView.onAppear` also calls `shopping.pruneOwned(...)` so the count in the label is never stale.

### Shopping list screen — new `ShoppingListView`

- `onAppear`: `pruneOwned`, then `browser.refresh(cabinet:taxonomyStore:)` so suggestions use the current cabinet.
- **Buy next** (≤ 5 rows, `BuyNextRow`): name; subtitle "+3 ready now · Last Word, Alaska, +1", or "Gets N recipes closer" when `readyNow` is 0; trailing 44 pt `cart.badge.plus` button labelled "Add ‹name› to shopping list".
- **Your list (N)** (`ShoppingItemRow`): leading 44 pt checkbox (`circle` only; the row leaves on tick, so there is no filled state) labelled "Bought ‹name›, move to cabinet"; name and family; swipe to delete. A ghost item (style left the catalog) is dimmed, reads "No longer in the catalog", has a disabled checkbox, and can still be deleted.
- **Loading:** while the catalog is loading (or recipe entries haven't been computed yet) the screen shows a progress view instead of the "Nothing to buy" state.
- **Empty states:** empty list + suggestions → only Buy next; nothing to suggest and empty list → "Nothing to buy — your cabinet covers every recipe"; empty cabinet still shows suggestions (ranked by `movesCloser`).
- **Undo toast** (`UndoToast`): "Moved ‹name› to your cabinet · Undo", 8 s, not auto-dismissed while VoiceOver is running; a new tick replaces it. The toast has a Dismiss (✕) button, which is how VoiceOver users close it; ticking also posts a VoiceOver announcement. Success haptic on tick. Rows slide out unless Reduce Motion is on.

### Recipe screen — `RecipeDetailView` / `IngredientRowView`

- A missing-ingredient row gets a second trailing 44 pt button: `cart.badge.plus` ("Add ‹name› to shopping list") or, when already listed, `cart.fill` in the accent colour ("Remove ‹name› from shopping list") which removes it. Existing add-to-cabinet button unchanged. At accessibility text sizes the buttons move below the ingredient text.
- With ≥ 2 missing ingredients, an "Add all missing to shopping list (N)" button under the Ingredients heading; disabled when all are listed.
- After the existing add-to-cabinet flow, call `shopping.pruneOwned(...)` (an owned item must leave the list).

### Wiring

- `ModelContainer(for: CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self)` in `NorseMixologyApp`; one `ShoppingListViewModel` created beside the Favourites and Cabinet view models and injected via `.environment`.
- New app-target files are registered with `xcodegen generate`; new strings go into `Localizable.xcstrings` via `sync-strings.sh`.

---

## 4. Failure modes

| Failure | Behaviour | Test |
|---|---|---|
| Existing store (cabinet + favourites) opened with the new schema | Lightweight migration; cabinet and favourites intact | Build an on-disk store with the old two-model schema, reopen with three, assert contents |
| Add the same style twice | `.alreadyListed`, no duplicate | Unit test |
| Add a style that is in the cabinet | `.alreadyOwned`, nothing stored | Unit test |
| Style enters the cabinet by another route | Removed by `pruneOwned` on next Cabinet/Shopping appear and after a recipe-screen add | Unit test |
| App killed between "cabinet add" and "list remove" | Item on both; `pruneOwned` clears it; nothing lost | Unit test simulating the interrupted state |
| Style leaves the catalog | Ghost row: dimmed, not tickable, removable; excluded from ranking | Unit test on `entries(in:)` |
| Undo after the cabinet item was deleted by hand | Skips cabinet removal, still re-adds to list | View-model test |
| Two ticks in quick succession | Toast shows the latest; earlier tick stays moved | Manual check |
| Empty cabinet | Suggestions ranked by `movesCloser`; no crash | Unit test |
| Nothing missing anywhere | Empty suggestions → "Nothing to buy" state | Unit test |
| Identical scores | Stable order (name ascending) | Unit test |
| Active taste profile | Breaks ties only; never overrides `readyNow`/`movesCloser` | Unit test |
| Stale suggestions after a cabinet change | Shopping screen refreshes the browser view model on appear | View-model test |
| Performance | Ranking 158 entries (30-item cabinet) < 100 ms | Extend the existing budget test |
| New Swift file not compiled | `xcodegen generate`; verify each new file in a `SwiftCompile` build-log line | Build check |
| Large text / Reduce Motion / VoiceOver | Buttons move below text; no slide animation; labels on every icon-only button; toast persistent under VoiceOver | Manual check (simulator) |

---

## 5. Testing

- **Core unit tests:** `ShoppingServiceTests`, `ShoppingListViewModelTests` (add/duplicate/owned/prune/addAll/entries/ghost/interrupted tick-off), `BuyNextRankingTests` (ordering keys, ties, taste tie-break, exclusion of listed styles, empty cabinet, nothing missing, limit), migration test, performance test.
- **Simulator verification (not yet possible — access not granted):** add three Last Word ingredients from its recipe screen; tick one off and see it in the cabinet; undo; confirm Buy next counts update; repeat on iPad width; check VoiceOver, Reduce Motion and large text.

---

## 6. Out of scope

Typing or picking an ingredient to add to the list by hand, quantities, sharing or exporting the list, notifications, bottle scanning (next roadmap item), free-text items (D), Android.
