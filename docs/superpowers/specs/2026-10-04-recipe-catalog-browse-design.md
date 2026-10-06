# Recipe Catalog Browse — Design

**Date:** 2026-10-04
**Status:** Implemented 2026-10-05
**Scope:** iOS only (Android paused). Sub-project **A** of the post-MVP feature roadmap (§7).

---

## 1. Goal and decisions

Today the Recipes tab only shows recipes the cabinet can make; anything with an unresolved required ingredient is dropped by the matching engine. This release lets the user **browse the whole catalog**, **search and filter** it, see **exactly what each recipe is missing**, and **add a missing ingredient to the cabinet** straight from the recipe screen.

Guiding principle: **failure first, additive only.** The matching engine's behaviour and public interface do not change (same rule as Phase 11's `TasteRanking`). Invariant: *a recipe is "Ready" in All recipes if and only if it appears in Can make.*

| Decision | Choice | Why |
|---|---|---|
| Placement | Segmented **Can make \| All recipes** toggle at the top of the Recipes tab | No new tab; Can make stays exactly as built |
| Search scope | Recipe name **and** ingredient style/family names; applies to **both** modes | "campari" should find every Campari drink |
| Filters | Apply to both modes; AND across filter kinds, OR within one kind | Predictable; matches common filter UIs |
| All recipes ordering | Sections **Ready / Missing 1 / Missing 2 / Missing 3+**, taste-ranked within each | "Missing 1" is a natural shopping hint and feeds sub-project B |
| "Missing" definition | Computed by the engine's own per-ingredient `resolve` | One source of truth — no approximation that can disagree with the engine |
| Engine change | `MatchingService.resolve` goes `private` → `internal`; nothing else | Smallest possible touch; no signature or Kotlin-parity change |
| Add action | "Add to cabinet" on each missing ingredient; shopping list arrives in B | Small, independently shippable spec |

Rejected: approximating "missing" as "no same-family item in cabinet" (can contradict the engine when a same-family item is below the similarity threshold); extending `MatchingService.match` to return dropped recipes (changes an interface both platforms depend on).

---

## 2. Core logic (`NorseMixologyCore`)

### Types

```swift
/// One catalog recipe evaluated against the cabinet.
public struct CatalogEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { recipe.id }
    public let recipe: Recipe
    public let match: RecipeMatchResult?          // non-nil ⇔ makeable now (engine's own result)
    public let substitutions: [SubstitutionDetail] // resolved-by-substitute ingredients, even when not makeable
    public let missing: [IngredientStyle]          // required + unresolvable, in recipe order
    public var tier: AvailabilityTier { get }
}

public enum AvailabilityTier: CaseIterable, Sendable { case ready, missing1, missing2, missing3Plus }

public enum CatalogAvailability {
    public static func evaluate(
        recipes: [Recipe], cabinet: [CabinetItem],
        taxonomyCategories: [IngredientCategory], prefs: MatchPreferences = .default
    ) -> [CatalogEntry]
}

public struct RecipeFilter: Equatable, Sendable {
    public var query: String
    public var criteria: [Criterion]      // AND across kinds, OR within one kind
    public enum Criterion: Hashable, Sendable {
        case tag(String)                  // curated style tag
        case strength(Strength)
        case baseFamily(UUID)
        case glass(GlassType)             // existing enums, not strings
        case method(Method)
        case difficulty(Difficulty)
    }
    public mutating func toggle(_ c: Criterion)
    public mutating func remove(_ c: Criterion)
    public func contains(_ c: Criterion) -> Bool
    public mutating func clear()
    public var isEmpty: Bool { get }
    public func matches(_ recipe: Recipe, index: TaxonomyIndex) -> Bool
}

public struct GroupedAvailability: Equatable, Sendable {
    public let ready, missing1, missing2, missing3Plus: [CatalogEntry]
    public init(entries: [CatalogEntry], profile: UserTasteProfile)  // taste-ranked within each tier
}

/// Pure browse state so it is unit-testable (the app target has no test target).
public struct RecipeBrowseState: Equatable, Sendable {
    public enum Mode: String, Sendable { case canMake, all }
    public var mode: Mode
    public var filter: RecipeFilter
}
```

The existing `RecipeAvailability` (ingredient-row status in `RecipePresentation.swift`) is unchanged; the new names avoid that collision.

### Evaluation

1. Run `RecipeService.findRecipes` once → `matchById`. A recipe in `matchById` gets `match` and `substitutions` from that result and `missing = []`.
2. For every other recipe, walk its ingredients using the same index, role derivation and `resolve` as `MatchingService.match`:
   - `.resolved` with a different substitute style → append a `SubstitutionDetail` (same note/ratio-hint builders as the engine).
   - `.unresolved` and the ingredient is **not soft** (soft = `isOptional || role == .garnish`) → append the required style to `missing`.
3. Ingredients whose style id is not in the index are skipped, exactly as the engine does.
4. `tier`: `match != nil` → `.ready`; else by `missing.count` (1, 2, ≥3).

Invariant guard: if a non-matched recipe ends up with `missing.isEmpty` (should be impossible), log at `.fault` and place it in `.missing1` with no add actions rather than in Ready — the UI must never show "Ready" for something Can make does not list.

### Search and filters

- **Query:** trimmed; empty matches everything. Case- and diacritic-insensitive (`localizedStandardContains`), so "creme" finds "Crème de violette". Matches recipe name, then each ingredient's style name and family name.
- **Strength:** `no-abv` tag → `.noABV`; `low-abv` tag → `.lowABV`; otherwise `.regular`.
- **Base spirit:** family of the ingredient(s) `RoleDerivation` classifies as `.base`.
- **Style tags (curated):** sour, tall, spirit-forward, refreshing, tiki, creamy, sparkling, bitter, smoky, dessert. Tags not in this list are ignored by the filter UI.
- **Glass, method, difficulty:** recipe fields as-is; option lists are derived from the loaded catalog, so new catalog values appear automatically.
- Can make filters the already-built `GroupedMatchResults` (no re-match), so its tiering and reveal animations are unaffected.

---

## 3. App (`ios/NorseMixology`)

### Recipes tab — `RecipeBrowserView` / `RecipeBrowserViewModel`

- Segmented `Picker` (Can make | All recipes) under the title; `.searchable` search field; active-filter chip row plus a **Filters** button opening a sheet with every filter. Filter chips keep a 32 pt capsule with a 44 pt hit area.
- `RecipeBrowserViewModel` gains `browseState: RecipeBrowseState`, `entries: [CatalogEntry]`, `groupedAvailability`. `refresh` computes both the existing match results and the catalog entries from one cabinet read.
- Mode persists across launches via `@SceneStorage`; query and filters persist across tab switches (view model) but not relaunch.
- **All recipes** renders a new `CatalogList`: sections Ready / Missing 1 / Missing 2 / Missing 3+ (empty sections hidden), compact rows (name, glass icon, status text: "Ready", "1 sub", the missing ingredient's name, or "Missing N"). No hero sweep or staggered entrance.
- iPad: both modes drive `selectedRecipeID`; if the selection leaves the filtered list it clears (existing behaviour).

### Recipe screen — `RecipeDetailView`

- New initialiser taking a `CatalogEntry`; existing initialisers stay for Favourites. Rows come from the existing `RecipeAvailability.rows(for:substitutions:cabinetStyleIds:)` using `entry.substitutions`.
- Rows whose style is in `entry.missing` get a trailing `plus.circle` button (≥ 44 pt hit area; VoiceOver label "Add ‹name› to cabinet"). Optional/garnish rows that are unavailable get **no** button.
- Tapping opens the existing `AddIngredientConfirmationView`. On confirm: cabinet add → browser `refresh` → the open screen re-reads its entry by id and updates in place; success haptic; VoiceOver announcement "Added to cabinet".
- A single `CabinetViewModel` is created at the app root and injected via `.environment` (like `FavouritesViewModel`); `CabinetView` uses it instead of constructing its own, so Cabinet and Recipes never disagree.

### Empty states

- Filter/search matches nothing: "No recipes match" + **Clear filters** button.
- Empty cabinet, All recipes: full catalog in Missing sections (doubles as discovery).
- Empty cabinet, Can make: existing copy unchanged.

---

## 4. Failure modes

| Failure | Behaviour | Test |
|---|---|---|
| Ready set disagrees with Can make | Impossible by construction (Ready = `findRecipes` output) | Parity test over full catalog × several fixture cabinets |
| Non-matched recipe with empty `missing` | `.fault` log; shown in Missing 1 without add buttons, never Ready | Unit test with a crafted recipe/cabinet |
| Empty cabinet | Every recipe lists all hard ingredients as missing; none dropped | Unit test: count == catalog count |
| Ghost cabinet style (removed from catalog) | Never substitutes (existing `resolve` guard) | Extend `CatalogToleranceTests` to `evaluate` |
| Dangling ingredient style id | Skipped, as the engine does | Unit test |
| Performance | 158 recipes × 30-item cabinet `evaluate` + filter < 100 ms | Extend existing performance test |
| Query edge cases (whitespace-only, emoji, 1 000-char, RTL text, diacritics) | Whitespace-only = no filter; others match by substring or not at all, never crash | Unit tests |
| Add for a style already in cabinet | `CabinetViewModel.add` no-ops; button hidden since style can't be in `missing` | Unit test on `missing` |
| Recipe leaves catalog while open | Entry re-lookup fails → "This recipe is no longer available" | Manual check (catalog swap applies next launch, so low risk) |
| New Swift file not compiled (hand-maintained `project.pbxproj`) | Each new file gets explicit pbxproj entries | Verify every new file in a `SwiftCompile` build-log line |
| Localisation | All new UI strings in `Localizable.xcstrings` via `sync-strings.sh` | Build-time check |
| Reduce Motion / large text | Tier moves after an add are not animated under Reduce Motion; filter chips wrap, never truncate | Manual check in simulator |

---

## 5. Testing

- **Core unit tests (new `CatalogAvailabilityTests`, `RecipeFilterTests`):** parity, missing ordering, soft-ingredient exclusion, substitutions on non-makeable recipes, tiers, taste ordering within tiers, every filter kind, AND/OR semantics, query edge cases, `RecipeBrowseState` mode switch keeps filter, adding a style moves a recipe from Missing 1 → Ready.
- **Performance:** extend the existing budget test.
- **Simulator verification (no UI test target exists):** cabinet London Dry Gin + Lime Juice + Maraschino Liqueur → search "chartreuse" → open Last Word → Add Green Chartreuse → Last Word shows Ready in All recipes and appears in Can make. Repeat at iPad width and with VoiceOver labels inspected.

---

## 6. Out of scope

Shopping list, "what to buy next" (B); bottle scanning; notes/ratings/photos/log (C); custom recipes and ingredients (D); backup/iCloud (E); on-device AI (F); Android parity.

---

## 7. Roadmap context (agreed 2026-10-04)

Each item gets its own spec → plan → implementation cycle.

1. **A — Browse catalog** (this spec)
2. **B — Shopping list + "what to buy next"** (single bottle that unlocks the most recipes)
3. **Bottle scan** — VisionKit label/barcode → cabinet or list
4. **C — Notes, ratings, photos + "made it" log** (overlay keyed by `recipeId`, SwiftData; photos via `PhotosPicker`, stored on device)
5. **D — Custom ingredients and recipes**, incl. "make my version" of a catalog recipe (matching engine must accept user recipes; custom ingredients need family + flavour profile)
6. **E — Backup** — export/import file + optional iCloud sync; ships with or right after D
7. **F — On-device AI** (Foundation Models, iOS 26 + Apple Intelligence, gated; min iOS stays 17): natural-language search, twist suggestions, recipe/ingredient drafting with guided generation constrained to catalog ids. **Spike first:** whether the model's guardrails handle alcohol content.
