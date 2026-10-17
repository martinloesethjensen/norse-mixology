# Pantry Staples — Design

**Date:** 2026-10-06
**Status:** Part 1 implemented 2026-10-06 (not yet verified on a Mac). Part 2 open.
**Scope:** iOS only (Android parked, #3). Issue #5. Builds on the shopping list (B) and the substitution fixes in #1.

---

## 1. Goal and decisions

Nobody thinks of sugar, eggs or soda water as bar stock. A new user who adds only spirits sees every sour and fizz drop out of "Can make", even though they could make one in a minute. Let the user say once which kitchen basics they have, and treat those as always in stock.

Guiding principle: **additive only.** The matching engine, `CatalogAvailability`, `BuyNextRanking` and the SwiftData schema don't change. They are given the cabinet plus the pantry.

| Decision | Choice | Why |
|---|---|---|
| Storage | `UserDefaults` set of `PantryStaple` raw values (`PantryStore`) | A preference, not inventory. No SwiftData migration, and no `CabinetItem` flag every cabinet screen would have to filter |
| Matching | `Pantry.effectiveCabinet` appends an **unsaved** `CabinetItem` per covered style | The engine already treats `CabinetItem`s as owned; nothing downstream needs to know about pantries |
| Where it applies | `RecipeBrowserViewModel.refresh(cabinet:)` and the Favourites detail | `refresh(cabinet:)` feeds Can make, All recipes, the recipe screen and Buy next. Favourites builds its own match |
| Buy next | Never suggests a pantry style, by construction | Pantry styles are in the effective cabinet, so they're never `missing` |
| Granularity | 7 everyday staples, each covering several catalog styles by name | "Lemons and limes" is one choice, not six (fresh fruit, juice, twist, wedge) |
| Default | Nothing chosen | Pre-release; onboarding (part 2) will offer the choice up front |

Rejected: pantry items as `CabinetItem`s with a flag (schema migration; the Cabinet, shopping list and every count would have to filter them); a pantry `ShoppingItem`-style model (it isn't data the user curates, it's a setting).

---

## 2. Core logic (`NorseMixologyCore`)

```swift
public enum PantryStaple: String, CaseIterable, Sendable, Identifiable {
    case sugar, honey, eggs, sodaWater, lemonsAndLimes, oranges, salt
    public var styleNames: [String]   // catalog styles it covers, by name
}

public enum PantryStore {           // UserDefaults, injected for tests, like TasteProfileStore
    static func load(defaults:) -> Set<PantryStaple>   // unknown raw values dropped, not the whole set
    static func save(_:defaults:)
}

public enum Pantry {
    static func styleIds(for:index:) -> Set<UUID>
    static func effectiveCabinet(_ cabinet:, staples:, index:) -> [CabinetItem]   // cabinet first, extras in name order, never inserted
}
```

| Staple | Covers |
|---|---|
| Sugar | Simple Syrup, Demerara Syrup, Sugar Rim |
| Honey | Honey Syrup |
| Eggs | Egg White |
| Soda water | Club Soda |
| Lemons and limes | Fresh Lemon, Fresh Lime, Lemon Juice, Lime Juice, Lemon Twist, Lime Wedge |
| Oranges | Fresh Orange, Orange Juice, Orange Wheel, Orange Twist |
| Salt | Kosher Salt Rim |

Names missing from the loaded catalog are ignored, so an over-the-air catalog change can't break a saved pantry. A test asserts that every name exists in the bundled catalog.

---

## 3. App (`ios/NorseMixology`)

### Part 1 (this change)

- **Settings → Pantry:** one toggle per staple, saved on change. Footer: "Recipes treat these as always in stock. They stay out of your cabinet and are never suggested to buy."
- `RecipeBrowserViewModel.refresh(cabinet:)` and `FavouriteRecipeDetail` match against `Pantry.effectiveCabinet(...)`. The Recipes and Shopping list screens already refresh on appear, so a Settings change applies the next time they're shown.
- No new app-target files, so `project.pbxproj` is untouched. New strings go into `Localizable.xcstrings` via `sync-strings.sh`.

### Part 2 (next)

- **Onboarding:** after the taste quiz, one "What's usually in your kitchen?" step with the same toggles, Sugar, Soda water and Lemons and limes pre-selected, and Skip.
- **Recipe screen:** pantry-covered rows show a small "Pantry" label instead of the cabinet tick. Simple and demerara syrup rows get a one-line tip ("1:1 sugar and hot water, stirred until dissolved").
- **Cabinet empty state:** a link to the pantry when it's empty.

---

## 4. Failure modes

| Failure | Behaviour | Test |
|---|---|---|
| Staple name not in the loaded catalog | Ignored | `testEveryStapleNamesRealCatalogStyles` guards the bundle |
| Unknown saved staple (removed in a later version) | Dropped, rest kept | `testUnknownStaplesAreDroppedNotTheWholePantry` |
| Cabinet already owns a pantry style | Not duplicated | `testStaplesAddOneItemPerStyleTheCabinetLacks` |
| Pantry item saved to SwiftData by accident | Never inserted (`modelContext == nil`) | Same test |
| Buy next suggests a staple | Impossible by construction | `testBuyNextNeverSuggestsAPantryStyle` |
| Empty cabinet, pantry only | Non-alcoholic drinks can be Ready; spirit drinks still need a spirit | Manual check |
| Performance | One extra map over ≤ 17 styles per refresh | Existing budget test covers `refresh` |

---

## 5. Testing

- **Core unit tests (`PantryTests`):** store round trip and tolerance, catalog coverage, effective cabinet, a Daiquiri from rum + pantry, Buy next exclusion.
- **Simulator (part 1):** Settings → Pantry → enable Sugar and Lemons and limes; with only White Rum in the cabinet, the Daiquiri appears in Can make as a Perfect Match; Buy next never lists syrup, juice or soda.

---

## 6. Out of scope

Pantry quantities or expiry, custom pantry items (D), syncing the pantry (E), Android.
