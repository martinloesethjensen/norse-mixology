# Norse Mixology — Build Reference

> Single source of truth for architecture decisions in this repo. Full design rationale and phase-by-phase checklists live in the Obsidian vault (`Project Ideas/Dev Project Ideas/Norse Mixology/`) — this file is the condensed reference Claude Code (or any contributor) reads before starting a phase.
>
> ```
> Read NORSE_MIXOLOGY_BUILD.md in full. Then build Phase N. Do not continue to Phase N+1.
> ```

A mixology app where you tell it what's in your cabinet and it finds the cocktails you can make — with smart substitution for what you're missing, computed entirely on-device.

## Platform status

**Android is parked until after the iOS launch** (decided 2026-10-06, [#3](https://github.com/martinloesethjensen/norse-mixology/issues/3)). Until it resumes:

- New work is iOS-only. Don't port features to Kotlin or keep the Kotlin matcher in sync. The "Swift and Kotlin must match exactly" rules below describe the target for when Android resumes, not current work.
- Keep the Android build green on what already exists: `scripts/sync-catalog.sh` still updates `/seed-data`, and `SeedDataTest` still checks it against the iOS bundle. Bump `CatalogSeeder.CATALOG_VERSION` whenever `/seed-data` changes.
- Record parity debt in #3 (and #2 for the matching engine), not as per-phase notes in this file.

## MVP Scope

- ✅ Local-first: cabinet + favourites + recipe catalog all on-device (SwiftData on iOS, Room on Android)
- ✅ Two platforms: iOS (SwiftUI) + Android (Jetpack Compose), phone and tablet
- ✅ Anonymous — no login required
- ✅ Smart substitution, computed entirely on-device
- ❌ No backend/network calls in MVP (Rust backend is a later release)
- ❌ No tvOS/macOS in MVP
- ❌ No user accounts, no social/sharing

## Tech Stack

| Layer | iOS | Android |
|---|---|---|
| UI | SwiftUI | Jetpack Compose |
| Local storage | SwiftData | Room |
| State management | `@Observable` view models | `ViewModel` + `StateFlow` |
| Navigation | `TabView`/`NavigationStack`, `NavigationSplitView` at tablet width | Navigation 3, `NavigationSuiteScaffold` |
| Networking | none in MVP | none in MVP |
| Min OS | iOS 17 | Android 8.0 / API 26 |

## Repo Layout

```
norse-mixology/
├── ios/
│   ├── project.yml                    ← xcodegen spec (regenerate with `xcodegen generate`)
│   ├── NorseMixology.xcodeproj         ← generated, not hand-edited
│   ├── NorseMixology/                  ← app target (SwiftUI views, assets)
│   └── Packages/NorseMixologyCore/     ← local SPM package: Models/, Services/, Taxonomy/
└── android/
    └── app/
        ├── data/{local,seed,repository}/
        ├── domain/matching/
        └── ui/{cabinet,recipes,favourites,theme}/
```

Neither platform has a `Networking/`/`networking/` folder — there is no server counterpart in MVP.

## Data Model & Matching Engine

Full taxonomy tables (spirits, liqueurs, mixers, syrups, garnishes, etc.) are in the vault's `Data Model.md`. Key shapes both platforms must realize field-for-field:

**Ingredient hierarchy:** `IngredientCategory → IngredientFamily → IngredientStyle`, each `IngredientStyle` carrying a `FlavorProfile`, an ABV range, and example brands.

**FlavorProfile** — normalized 0.0–1.0 scores: `sweetness, bitterness, smokiness, citrus, floral, spice, herbal, fruity, oaky`, plus `abv` (actual percentage).

**Recipe** — `id, name, description, glassType, method, ingredients: [RecipeIngredient], steps, flavorProfile, tags, difficulty, imageURL`. `RecipeIngredient` — `ingredientStyleId, amount, preparation, isOptional, substituteNotes`. Bundled in `recipes.json`, seeded into local storage on first launch on both platforms (no server round-trip — the two implementations only need to agree on JSON shape).

**CabinetItem** — `id, ingredientStyleId, ingredientFamilyId, categoryId, displayName, brand, style, family, category, flavorProfile, dateAdded`.

**FavouriteRecipe** — `id, recipeId, recipeName, dateFavourited`.

On Android, Room has no native array-of-struct column, so `Recipe.ingredients` becomes a separate `RecipeIngredient` table with a `recipeId` foreign key, loaded via `@Relation`/`@Transaction` so callers still see a single `Recipe` + `List<RecipeIngredient>`.

### Matching algorithm (single source of truth — Swift and Kotlin must match this exactly)

```
resolve(required, cabinet, prefs):
  if user rule .reject(required → X)      → X is forbidden
  if user rule .accept(required → X)      → quality = 1.0        (user overrides math)
  if exact style in cabinet               → quality = 1.0
  if enabled curated rule covers it       → quality = rule.baseQuality
  else best same-family cabinet item:
      sim = cosineSimilarity(required.profile, candidate.profile)
      if sim >= threshold(prefs.strictness) → quality = sim
      else                                  → UNRESOLVED
```

A recipe with any `UNRESOLVED` required ingredient is dropped from results.

- **Cosine similarity** is computed over the 9 flavour dimensions (excludes `abv`). Substitute-display threshold: similarity ≥ 0.55.
- **Strictness → threshold:** `threshold = 0.45 + strictness * 0.40` (strictness `0`…`1` → threshold `0.45`…`0.85`).
- **matchScore** (recipe-level, weighted by ingredient role):
  `matchScore = 1 - (Σ roleWeight(role) · (1 - quality) / Σ roleWeight(role))`
  Default role weights: Base `1.0`, Modifier `0.8`, Sweetener/Sour `0.6`, Bitters/Mixer `0.4`, Accent `0.3`, Garnish `0.1`.
  `matchScore = 1.0` → `"exact"`; `0.55–0.99` → `"partial"`.

If the two platform implementations ever disagree, this section — not either codebase — is the tiebreaker.

**Deriving `role` (not a stored field):** `RecipeIngredient` has no `role` field, so role is derived at match time from the ingredient's taxonomy category/family — both platforms must apply this exact mapping:

| Category | Family | Role |
|---|---|---|
| Spirit | — | `Base` (largest ml amount among the recipe's Spirit ingredients) else `Modifier` |
| Wine & Fortified | — | `Modifier` |
| Liqueur | — | `Accent` |
| Syrup | — | `Sweetener/Sour` |
| Mixer | Juice | `Sweetener/Sour` |
| Mixer | other | `Bitters/Mixer` |
| Garnish | Bitters | `Bitters/Mixer` |
| Garnish | other | `Garnish` |
| Fruit | — | `Garnish` |
| anything else | — | `Accent` (fallback) |

Garnish-role ingredients never drop a recipe (treated like an unresolved *optional* ingredient — skipped, no score penalty) regardless of the seed data's `isOptional` flag. This is why "Gin + Campari + Sweet Vermouth → Negroni, exact" holds even though the Negroni's orange-wheel garnish isn't flagged optional in `recipes.json`.

## Recipe Browser rules (Phase 4 — Android Phase 9 must match)

Pure presentation logic lives in `NorseMixologyCore` (`RecipePresentation.swift`, unit-tested) so both platforms apply identical rules:

- **Grouping** of match results: `matchType == exact` → **Perfect Match**; partial with ≤ 1 substitution → **Almost There**; partial with ≥ 2 substitutions → **Worth Exploring**. Order within a group is the engine's order (never re-sorted).
- **Card badge:** exact → "✓ All ingredients" (lime); partial → "1 sub needed" / "N subs needed" (gold). Results never contain recipes with an unresolved required ingredient, so there is no "missing" card badge.
- **Ingredient row status** (recipe detail): a reported substitution for that required style → *substituted* (wins even if the exact style is also in the cabinet, e.g. a user "accept" override); else exact style in cabinet → *exact*; else → *unavailable*. Only optional/garnish ingredients can be unavailable — e.g. a Negroni with gin/Campari/vermouth is a Perfect Match whose orange-wheel row shows unavailable.
- **Where results live:** the Recipes tab hosts the browser and re-matches whenever it appears (and on pull-to-refresh). Cabinet's "Find Recipes" re-matches and switches to the Recipes tab.
- **Layout:** compact width pushes the detail screen; regular width shows a list/detail split inside the Recipes tab. The tab bar is kept on iPad — an app-wide sidebar shell was considered in Phase 6 and left as a post-MVP option (see the vault's Future Improvements).
- **Glass icons (SF Symbols):** coupe/martini/flute/wine glass → `wineglass`; rocks → `cup.and.saucer`; highball/collins/hurricane → `cylinder`; mug → `mug`.
- **Note:** a cross-family swap such as Vodka for Gin is *not* a substitution — vodka isn't in gin's family and there's no curated rule — so such a recipe drops out instead of moving to "Almost There". Use a same-family swap (e.g. Contemporary Gin for London Dry Gin) when checking that flow.

## Favourites rules (Phase 5 — Android Phase 9 must match)

- **Storage:** `FavouriteRecipe` = `id, recipeId, recipeName, dateFavourited` — `recipeId` points at the bundled catalog, `recipeName` is cached for the list row. One record per recipe (saving an already-saved recipe is a no-op) and every change is saved immediately, not left to autosave.
- **Order:** most recently favourited first.
- **State is shared app-wide:** one `FavouritesViewModel` (injected at the app root) backs the detail-screen heart, the filled heart on result cards, and the Favourites tab, so they never disagree. On iOS it lives in `NorseMixologyCore/ViewModels/` so it can be unit-tested.
- **Heart:** toggles favourite; brief scale bounce + medium haptic (skip the bounce under Reduce Motion).
- **Opening a favourite:** the recipe is looked up in the bundled catalog by `recipeId` (synchronous, no loading state), and availability is computed against the *current* cabinet. If the cabinet can no longer make it the matching engine returns no result: show a "Missing ingredients" pill, ingredient rows as exact/unavailable only, and no substitution callout.
- **Recipe no longer in the catalog:** keep the cached-name row, dimmed and non-navigable, still removable via swipe.
- **Swipe** a row to unfavourite.
- **iOS migration note:** `FavouriteRecipe` was a one-field stub in Phases 0–4. Its new attributes have default values so SwiftData upgrades existing stores in place (verified on a simulator store created by the Phase 4 build). Room on Android starts fresh, so this doesn't apply there.

## Hardening rules (Phase 6 — Android Phase 10 must match)

- **Tolerant catalog parsing:** a malformed recipe entry is skipped (and logged with the skipped count) instead of failing the whole catalog. A file that isn't a JSON array at all is still an error.
- **Duplicate ingredient:** tapping an ingredient already in the cabinet shows a transient "Already in your cabinet" notice (~2 s, announced to the screen reader). Ingredient rows are real buttons, not tap gestures, so assistive tech can activate them.
- **Empty results:** "Your cabinet didn't match any recipes. Try adding some base spirits like gin, rum, or vodka."
- **Unavailable favourite:** "This recipe is no longer available".
- **Flavour indicator:** superseded by flavour notes — see "Flavour notes (iOS)" below (the five dots were retired).
- **Design tokens everywhere:** no screen defines its own colour or font size. Match-status colours are used identically on cards, badges and ingredient rows.
- **Large text:** header pills stack rather than wrap mid-word; icon slots and step badges scale with the text; buttons grow with their label (min 44 pt).
- **Logging:** structured logging only (`os.Logger` on iOS, `Log` on Android) — no `print`.
- **Localisation-ready:** iOS keeps UI strings in a String Catalog (`ios/NorseMixology/Localizable.xcstrings`; `ios/scripts/sync-strings.sh` refreshes it after a CLI build). Android uses `strings.xml`. Not yet localisable on iOS: strings produced by the core package (badge labels, glass/method/difficulty names, substitution notes assembled from English fragments) — see Future Improvements.
- **Performance budget:** matching a 30-item cabinet against the full catalog (~158 recipes) must stay well under 100 ms (measured ~8 ms on a Mac debug build; a unit test enforces it).

## Catalog delivery (iOS)

- **Source:** `https://martinloeseth.dev/norse-catalog/v1/manifest.json` → content-hashed `taxonomy.<sha8>.json` / `recipes.<sha8>.json`. Spec: `docs/superpowers/specs/2026-09-23-catalog-delivery-design.md`.
- **On device:** `Application Support/Catalog/catalog.sqlite` (GRDB, `STRICT` tables, foreign keys, 0–1 `CHECK`s, `user_version` = `CatalogSchema.version`). Built only by `CatalogImporter` from hash-verified JSON; read only by `CatalogDatabase` (read-only, then closed — `TaxonomyStore` holds the catalog in memory).
- **Launch:** `CatalogBootstrap` removes staging leftovers, loads the live DB, and rebuilds from the bundled snapshot if it's missing, corrupt, a different schema version, or older than the bundle. If that fails it keeps an older valid DB, else the app shows "Catalog unavailable".
- **Refresh:** `CatalogUpdater` runs after the UI is up on every cold launch: conditional GET with the stored ETag, 64 KB manifest cap, 2 MB file caps enforced while streaming, SHA-256 checks, import into `catalog.new.sqlite`, atomic replace. New content applies on the **next** launch. A manifest whose `generatedAt` isn't newer than the current catalog is ignored.
- **Bump `CatalogSchema.version`** whenever the SQLite schema changes; the bootstrap rebuilds on mismatch.
- **Remote updates reject the whole catalog on any malformed recipe** (unlike the tolerant bundled-era loader).
- **Styles removed from the catalog** stay in cabinets as snapshots but never act as substitutes (`MatchingService.resolve`).
- **Android parity:** the Kotlin matcher (paused) does not yet have these ghost-style guards; port both (accept override + family candidates) when Android adopts over-the-air catalog updates.
- **Before an app release:** run `scripts/sync-catalog.sh` so the bundled fallback is current.

## Android data layer & seeding (Phase 7)

- **Room 3, not Room 2.** Package is `androidx.room3`; type converters are `@ColumnTypeConverter` classes listed in `@ColumnTypeConverters`. `UUID` and enums use Room's *built-in* converters (enabled on the database), so only `Date` and `List<String>` need custom ones. Room 3 has no implicit driver: the app passes `AndroidSQLiteDriver()`.
- **JVM unit tests run real Room** against an in-memory database using the host-JVM SQLite driver (`androidx.sqlite:sqlite-bundled-jvm` — the plain `sqlite-bundled` resolves to the Android variant, which ships phone ABIs only and can't load on a Mac). Fast and no emulator needed for repository, seeder and view-model tests.
- **One catalog source of truth.** The catalog is authored in the public `norse-catalog` repo (`generate.py` → validated → published to GitHub Pages). `scripts/sync-catalog.sh` copies the published `manifest.json` + `taxonomy.json` + `recipes.json` into `/seed-data` and `ios/NorseMixology/Resources` (and the iOS core test resources). Android copies just `taxonomy.json` + `recipes.json` from `/seed-data` into generated assets at build time (`copySeedData` task). A unit test asserts that `ios/NorseMixology/Resources/*.json` is byte-identical to `/seed-data` — always update both via the sync script.
- **Seeding.** `CatalogSeeder` runs on a background coroutine at app start and writes the catalog tables in atomic replaces; a DataStore integer flag (`CatalogSeeder.CATALOG_VERSION`) records what's loaded. **Bump `CATALOG_VERSION` whenever `/seed-data` changes.** Reseeding replaces taxonomy/recipe tables only — the user's cabinet and favourites are never touched, which is why `CabinetItem` is a snapshot with no foreign key to the taxonomy.
- **Tolerant parsing** (same rule as iOS): a malformed recipe is skipped and counted, not fatal; a non-array file still fails.
- **Cabinet uniqueness** is enforced by the database (unique index on `ingredientStyleId`), not just the UI. `CabinetRepository.add` returns `false` for a duplicate.
- **Schema notes beyond the design doc:** `sortOrder` on category/family/style/recipe keeps the catalog's authored order for Browse; `RecipeIngredient.position` keeps ingredient order. `FavouriteRecipe` exists as a stub table so the v1 schema is stable. No destructive migrations, ever — a future schema change needs a real `Migration`.
- **Add-ingredient flow:** Cabinet → Add (Search | Browse) → Browse pushes Category → Family → Style on a Navigation 3 back stack. One `AddIngredientViewModel` (activity-scoped, `reset()` on entry) serves every screen so the confirmation `ModalBottomSheet`, hosted above the back stack, behaves identically from Search and Browse; after adding, the stack pops back to the Cabinet from any depth.
- **Tokens:** `ui/theme/Colour.kt` / `Type.kt` mirror the iOS tokens (dark/light pairs; dynamic colour deliberately off). On Android the selected nav item is a lime pill with a dark icon, which sidesteps the light-mode lime-on-white contrast problem noted for iOS.

## Android matching engine (Phase 8)

- **Direct Kotlin port, no shared code.** `domain/matching/{MatchingModels,SubstitutionEngine,MatchingEngine}.kt` reproduce iOS's `MatchingService`/`SubstitutionService`/`RoleDerivation` field-for-field and branch-for-branch — same threshold formula, same role-weight defaults, same curated-substitution table, same role-derivation table, same note-generation logic. `Taxonomy` (Phase 7's in-memory tree) stands in for iOS's `TaxonomyIndex`; no new lookup type was introduced.
- **Verified numerically identical, not just categorically.** The Old Fashioned Bourbon→Rye case scores `matchScore = 0.9176833072716362` on both platforms to the last digit (checked with matching throwaway test cases run on both engines side by side, then deleted); the Negroni case scores `1.0`/exact on both.
- **`MatchPreferences` is a plain data class** (`Map<IngredientRole, Double>`, no `Codable`-style String-keying) since nothing persists it yet — simpler than iOS's version by necessity, not by drift. Revisit if a preferences/strictness UI is ever added.
- **`RecipeRepository.load()`** joins `RecipeDao.recipes()` + `RecipeDao.recipeIngredients()` into a `RecipeCatalog` (a `List<RecipeWithIngredients>`), mirroring `TaxonomyRepository`'s shape. Loaded once into an `AppContainer` `StateFlow` alongside the taxonomy, after seeding.
- **"Find Recipes" wiring:** `RecipeMatchViewModel` is activity-scoped (like `AddIngredientViewModel`) so it's shared between the Cabinet screen and the results screen across Nav3 entries. Its state is a `sealed interface FindRecipesState { Idle, Loading, Ready(results, requestId) }` — **`requestId` is load-bearing, not decorative:** two searches over an unchanged cabinet produce a structurally-equal `results` list, and a plain `Ready(results)` would then be `==` the previous emission. `StateFlow` + `collectAsStateWithLifecycle` + `LaunchedEffect(state)` compose a nav trigger keyed on value equality, and Compose's rapid-emission batching can also collapse the transient `Loading` in between two `Ready`s — so a repeat "Find Recipes" tap could silently fail to navigate. The monotonically increasing `requestId` guarantees every `Ready` is a distinct key. Found by testing repeated taps on-device, not by the unit suite (it needs real StateFlow/Compose timing to surface).
- **`RecipeResultsScreen` is a deliberate stub** (name, match %, substitution count) — proves the engine end-to-end without pre-building Phase 9's real browser.

## Android recipe browser & favourites (Phase 9)

- **"Find Recipes" is a tab switch, not a push**, matching iOS's actual `CabinetView(onFindRecipes: { selectedTab = .recipes })`. `RecipeViewModel` is app-wide (created once in `NorseMixologyApp`, like iOS's `RecipeBrowserViewModel`) and re-matches in a `LaunchedEffect` keyed on the recipe catalog whenever the Recipes tab is (re)composed — there is no separate "results" screen or loading state, since matching is synchronous and near-instant. This replaced Phase 8's `RecipeMatchViewModel`/`RecipeResultsScreen` stub entirely.
- **`RecipeMatchResult` carries its ingredients.** Added `ingredients: List<RecipeIngredient>` to the Kotlin model (iOS doesn't need this — its `Recipe` struct embeds ingredients directly) so the detail screen can render a recipe's ingredient rows without a second catalog lookup.
- **Presentation logic lives in `domain/matching/RecipePresentation.kt`** (`GroupedMatchResults`, `MatchBadgeState`, `AvailabilityStatus`, `IngredientAvailability`, `RecipeAvailability`) — a direct port of iOS's `RecipePresentation.swift`, unit-tested the same way.
- **Two-pane breakpoint:** `LocalConfiguration.screenWidthDp >= 840` (Material 3's Expanded threshold), checked directly in `ui/isExpandedWidth()` rather than pulling in the full `material3-adaptive` window-size-class artifact for one boolean.
- **Favourites:** `FavouriteRecipe` now has a unique index on `recipeId` (Room enforces "one record per recipe" via `OnConflictStrategy.IGNORE`, not just the UI). `FavouritesViewModel` is app-wide (created once in `NorseMixologyApp`) so the heart on cards, the detail screen, and the Favourites tab always agree — mirroring iOS's `FavouritesViewModel`.
- **Substitution notes expand inline on tap** (a rotating chevron, matching iOS's `IngredientRowView`) rather than a `ModalBottomSheet` — the Phase 9 checklist's explicit instruction and iOS's actual behaviour are the authority here, not `Frontend - Android.md`'s earlier nav-diagram sketch.

## iOS taste profile & onboarding (Phase 11)

- **Additive only — the matching engine is never touched.** `TasteRanking` (`NorseMixologyCore/Services/TasteRanking.swift`) reads an already-computed `GroupedMatchResults` and rebuilds one via its existing public `init(results:)`; it never modifies `MatchingService`, `MatchPreferences`, `RecipeMatchResult`, `MatchType`, or the tier-bucketing rule above. `RecipeBrowserViewModel.refresh` calls it as one extra line right after building `GroupedMatchResults`.
- **`UserTasteProfile`** has exactly 5 quizzed axes (sweetness, bitterness, citrus, smokiness, herbal) plus `hasCompletedOnboarding` — deliberately no floral/spice/fruity/oaky, since defaulting those to neutral and comparing them would silently bias ranking toward recipes that happen to sit near 0.5 on axes the user was never asked about. `TasteRanking.similarity` is its own 5-axis cosine, not a reuse of the 9-axis `FlavorSimilarity.cosine` used by substitution matching.
- **`reorder` re-sorts every tier** (Perfect Match, Almost There, Worth Exploring), not just breaking ties in Perfect Match, per the checklist as built and reviewed — see the Phase 11 vault doc's Notes for the wording nuance against its own Objective. A no-op guard checks the 5 axis values directly (not `profile == .neutral`) since the onboarding Skip path saves a profile with neutral axis values but `hasCompletedOnboarding: true`, and both must be no-ops.
- **Persistence is a single JSON blob in `UserDefaults`** (`TasteProfileStore`, key `com.norsemixology.userTasteProfile`), with `UserDefaults` injected (default `.standard`) rather than hardcoded, matching this codebase's other testable-service pattern.
- **Existing-install migration runs synchronously in `NorseMixologyApp.init()`**, using the `ModelContainer.mainContext` already available there (same pattern as building `FavouritesViewModel`) — not in `ContentView.onAppear`, which would flash the tab bar before showing the quiz. An uncompleted profile on an install with any existing `CabinetItem`/`FavouriteRecipe` gets a neutral *completed* profile saved silently instead of seeing the quiz.
- **`ThisOrThatCard`'s gesture handling went through three iterations** before landing on a single `DragGesture(minimumDistance: 0)` that resolves tap-vs-swipe intent and which half was touched from one source of truth (`resolve(_:)`, using `startLocation.x` vs. a `GeometryReader`-measured card width for taps, and `translation.width`'s sign for committed swipes). Earlier attempts combined a real `Button` per half with a separate drag gesture — `.gesture()` alone blocked the buttons' taps entirely; `.simultaneousGesture()` let taps work but could fire both the drag and a phantom tap from one physical swipe, sometimes recording opposite choices for the same gesture. **If this card is ever touched again, do not reintroduce a `Button` alongside a drag gesture on the same view** — the single-recognizer design is load-bearing, not incidental. VoiceOver accessibility (each half independently focusable, announced as a button, double-tap to activate) is provided via `.accessibilityElement` + `.accessibilityAddTraits(.isButton)` + `.accessibilityAction`, not a literal `Button`.
- **`project.pbxproj` is hand-maintained, not file-system-synchronized** — a new Swift file under `ios/NorseMixology/` needs an explicit group/build-file/Sources-phase entry or it silently compiles out of the app target with no build error (discovered when Phase 11's first two onboarding files were added without this and nothing ever actually type-checked them). Verify new files actually appear in a `SwiftCompile`/`SwiftPerFileCompile` build log line, not just that `xcodebuild` reports success.
- **Large Dynamic Type accessibility support was descoped** for this phase by explicit user direction. A real truncation bug (`.frame(height:)` clipping quiz text) was fixed before the descoping decision and stays fixed; no further large-text polish was pursued.

## Recipe catalog browse (iOS)

- **Spec:** `docs/superpowers/specs/2026-10-04-recipe-catalog-browse-design.md`. Roadmap sub-project A.
- **Additive only.** `CatalogAvailability.evaluate` takes "Ready" from `MatchingService.match` itself and, for every other recipe, reuses the engine's per-ingredient `resolve` (now `internal`, not `private` — the only engine change) to list `missing` (required, unresolvable, recipe order, de-duplicated) and the substitutions that already work. Invariant, unit-tested: Ready in All recipes ⇔ listed in Can make.
- **Tiers:** Ready / Missing 1 / Missing 2 / Missing 3+ (`GroupedAvailability`). Ready ordered like the engine; Missing tiers by count then name; an active taste profile re-sorts within each tier (`TasteRanking.sorted`, same no-op rule as `reorder`).
- **Search & filters (`RecipeFilter`)** apply to both modes. Query: trimmed, case- and diacritic-insensitive, matches recipe name then ingredient style/family names. Criteria: strength (`no-abv`/`low-abv` tags), base spirit (family of the `.base`-role ingredient), curated style tags, glass, method, difficulty; AND across kinds, OR within one. Can make is filtered without re-running the engine.
- **Persistence:** mode in `@SceneStorage("recipes.browseMode")`; query and filters only for the session.
- **Add to cabinet:** only rows in `entry.missing` get the ⊕ button (never optional/garnish rows). One `CabinetViewModel` is injected at the app root and shared by Cabinet and the recipe screen. Favourites' detail has no add buttons.
- **Android parity:** not ported (Android paused). A port needs the same "Ready ⇔ engine result" rule.
- Filter chips and rows keep ≥ 44 pt hit areas; the add button is 44×44.

## Shopping list (iOS)

- **Spec:** `docs/superpowers/specs/2026-10-05-shopping-list-design.md`. Roadmap sub-project B.
- **Storage:** SwiftData `ShoppingItem` (one per `ingredientStyleId`, cached `styleName`) in the same container as `CabinetItem`/`FavouriteRecipe`; added as a lightweight migration (tested against an on-disk two-model store). Every change saved immediately.
- **Rules live in core:** `ShoppingListViewModel` (injected at the app root) — `add` refuses owned or listed styles, `addAll` counts what it added, `pruneOwned` drops listed styles now in the cabinet (run on Cabinet/Shopping appear and after a recipe-screen add).
- **Tick-off ordering:** `markBought` saves the cabinet insert *before* removing the list item, so an interruption leaves the bottle on both (repaired by `pruneOwned`), never on neither. `BoughtReceipt.createdCabinetItemId` makes undo remove only the cabinet item the tick created. Ghost items (style left the catalog) can't be ticked but can be deleted.
- **One way to build a cabinet item:** `CabinetItem.make(from:index:brand:date:)` — used by `CabinetViewModel.add` and by tick-off.
- **Buy next (`BuyNextRanking`)** reads `CatalogEntry.missing` only: ready-now count, then moves-closer count, then summed taste fit (only for an active profile), then name. Listed styles excluded; top 5. Covered by the refresh-pipeline budget test (< 100 ms).
- **UI:** Cabinet tab segment `Cabinet | Shopping list (N)` (`@SceneStorage("cabinet.segment")`). Undo toast for 8 s, or until Undo/Dismiss while VoiceOver runs. Recipe screen: cart button beside ⊕ on missing required ingredients, and "Add all missing" for ≥ 2.
- **Android parity:** not ported (Android paused).
- **Loading:** the Shopping list shows a progress view until recipes are loaded and evaluated, so it never claims "nothing to buy" from empty data.

## Flavour notes (iOS)

Replaces the five unlabelled "tasting dots". Design canvas: "Tasting Dots" (Claude Design artifact); rules below are what was built.

- **Five axes, one vocabulary:** `FlavorAxis` (Sweet, Bitter, Smoky, Citrus, Herbal — the taste quiz's axes, in the old dots' order). `FlavorNotes` turns a 0…1 `FlavorProfile` into words: a **note chip** at a score ≥ 0.5, strongest first, two at most; ≥ 0.67 is *strong* (tinted fill), 0.5–0.67 *mild* (outline); nothing ≥ 0.5 reads **Neutral**. Level words reuse `FlavorLevel` (Low < 0.34 ≤ Medium < 0.67 ≤ High) plus **None** below 0.05.
- **Recipes use their own scale.** A recipe's profile is a blend, so its scores run low (at 0.5 only 44 of 158 recipes would show a note; bitterness tops out at 0.44). `RecipeFlavorScale` divides each axis by the highest score any catalog recipe has on it (floor 0.2), then the same rules apply. It is rebuilt from the loaded catalog on every `RecipeBrowserViewModel.refresh`, so catalog updates re-calibrate it. Tests pin Negroni → Bitter + Herbal, Margarita → Citrus, and that between 5% and 35% of recipes read Neutral.
- **"You" is a diamond** (`YouMarker`), everywhere: on a recipe chip when the quiz says you lean toward that flavour (`TasteFit.axesLeaningToward`: answer ≥ 0.67), on each bar of the ingredient detail, and on the Settings lines. Nothing "you" is shown unless `TasteRanking.isActive` — an unfinished, skipped or all-0.5 quiz shows no diamonds on recipes/bars, and Settings shows dimmed diamonds at the centre with "No preference yet".
- **Where it appears:** note chips on Cabinet rows, the Add Ingredient picker, and recipe cards/rows (both Recipes modes); tapping a Cabinet row opens `IngredientDetailView` (headline, quiet notes, the "suits you" sentence from `TasteFit.summary`, then five labelled `FlavorBarsView` bars); the add-ingredient confirm sheet shows the bars directly; Settings → Your Taste is five `TasteLinesView` lines between the quiz's two answers.
- **Fit sentence:** the axis with the largest gap between ingredient and your answer (axes you have no opinion on are ignored); a gap under 0.35 reads "Close to your taste." It sits above the bars so it is visible at the sheet's default height.
- **Accessibility:** each chip's label is one whole phrase ("Bitter, strong", "Herbal, mild, matches your taste") so a row that combines its children never separates a strength from its flavour; each bar reads "Bitter, High. You: low". At accessibility text sizes the bar rows and the legend stack (checked at the largest size) and the diamond grows to at most 1.6×.
- **Retired:** `FlavorProfileIndicatorView` (the dots). `FlavorProfile.accessibilitySummary` stays (still tested) but is no longer used by a view.

## Design System — "Modern Neon Bar"

Both platforms follow system light/dark appearance (never forced). Same tokens, mapped for each mode:

| Token | Dark | Light |
|---|---|---|
| Background | `#0D0F14` | `#F7F8FA` |
| Surface | `#161920` | `#FFFFFF` |
| Surface Raised | `#1F232D` | `#EFF1F4` |
| Border | `#262B36` | `#DDE1E7` |
| Accent (lime) | `#8FE388` | `#8FE388` |
| Text Primary | `#EEF1F5` | `#14171C` |
| Text Secondary | `#9AA1AF` | `#5B6472` |

Match-status: Exact `#8FE388`, Substituted `#F0B93D` (both modes); Unavailable `#4A5160` dark / `#A6AEBA` light.

Typography (native system fonts — SF Pro on iOS, Roboto on Android): Display/Title 26sp/pt·800, Section Heading 16sp/pt·600, Body 13sp/pt·400 (secondary colour), Label/Badge 10sp/pt·700 uppercase.

The full palette is wired into every iOS screen as of Phase 6 (`Theme/DesignTokens.swift` is the only place colours and font sizes are defined); Android gets the same in Phase 10. Until then an Android screen uses its default theme, which already respects system appearance.

## iOS Architecture

- **Structure:** single Xcode project (`NorseMixology.xcodeproj`, generated via `xcodegen` from `project.yml`), one universal iOS+iPadOS target, local SPM package `NorseMixologyCore` (Models/, Services/, Taxonomy/, plus a test target) for business logic.
- **State:** `@Observable` view models exclusively — no Combine, no `ObservableObject`.
- **Navigation:** `TabView` + `NavigationStack` at compact width; `NavigationSplitView` (sidebar + detail) at regular width (iPad).
- **Persistence:** SwiftData `@Model` classes for `CabinetItem`/`FavouriteRecipe`; `taxonomy.json`/`recipes.json` bundled and seeded on first launch.
- **Bundle ID:** `dev.martinloeseth.NorseMixology`.

## Android Architecture

- **Structure:** single Android Studio project, one `app/` module, package layout above.
- **State:** `ViewModel` + `StateFlow`, collected via `collectAsStateWithLifecycle()` — no RxJava, no LiveData. Repository pattern between ViewModels and data sources (per current official Android architecture guidance).
- **Navigation:** Navigation 3 (`androidx.navigation3`) + `NavigationSuiteScaffold` — bottom bar at phone width, nav rail / two-pane list-detail at tablet width.
- **Persistence:** Room 3 (`androidx.room3`) `@Entity` data classes, KSP for annotation processing. `UUID`/`Date`/`List<String>` need `TypeConverter`s. `taxonomy.json`/`recipes.json` bundled in `assets/`, parsed with kotlinx.serialization, seeded on first launch (version-flagged to avoid reseeding).
- **Application ID:** `dev.martinloeseth.NorseMixology` (Kotlin source package stays lowercase, `dev.martinloeseth.norsemixology`, per Kotlin/Android convention — `applicationId` and `namespace` are independent settings).

## Build Phases

| Phase | Name |
|---|---|
| 0 | Project Setup — Xcode + Android Studio scaffolding |
| 1 | Ingredient Taxonomy & Data Model — author `taxonomy.json` + `recipes.json` |
| 2 | iOS: The Cabinet (SwiftData) |
| 3 | iOS: Recipe Matching Engine (Swift) |
| 4 | iOS: Recipe Browser & Results UI |
| 5 | iOS: Favourites |
| 6 | iOS: MVP Polish — dark/light theme system, tablet split view |
| 7 | Android: Cabinet & Taxonomy (Room, Compose) |
| 8 | Android: Recipe Matching Engine (Kotlin, same spec as Phase 3) |
| 9 | Android: Recipe Browser & Favourites |
| 10 | Android: MVP Polish — tablet layout, platform parity check against iOS |
| 11 | iOS: Taste Profile & Animated Onboarding — 5-question quiz, secondary ranking, Settings tab (iOS-only; Android paused) |

Build order: iOS first, end-to-end to a complete MVP, then port to Android.

## Full design docs

The Obsidian vault (`Project Ideas/Dev Project Ideas/Norse Mixology/`) has the complete picture: `Overview.md`, `Data Model.md` (full taxonomy tables), `Design System.md`, `Frontend - iOS.md`, `Frontend - Android.md`, `Deployment.md`, `Future Improvements.md`, and per-phase checklists under `Phases/`.
