# Norse Mixology — Build Reference

> Single source of truth for architecture decisions in this repo. Full design rationale and phase-by-phase checklists live in the Obsidian vault (`Project Ideas/Dev Project Ideas/Norse Mixology/`) — this file is the condensed reference Claude Code (or any contributor) reads before starting a phase.
>
> ```
> Read NORSE_MIXOLOGY_BUILD.md in full. Then build Phase N. Do not continue to Phase N+1.
> ```

A mixology app where you tell it what's in your cabinet and it finds the cocktails you can make — with smart substitution for what you're missing, computed entirely on-device.

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
- **Flavour indicator:** five dots (sweetness, bitterness, smokiness, citrus, herbal) in the accent colour, strength = value. Read aloud as one element: "Sweetness: high, Bitterness: low, …" with low < 0.34 ≤ medium < 0.67 ≤ high.
- **Design tokens everywhere:** no screen defines its own colour or font size. Match-status colours are used identically on cards, badges and ingredient rows.
- **Large text:** header pills stack rather than wrap mid-word; icon slots and step badges scale with the text; buttons grow with their label (min 44 pt).
- **Logging:** structured logging only (`os.Logger` on iOS, `Log` on Android) — no `print`.
- **Localisation-ready:** iOS keeps UI strings in a String Catalog (`ios/NorseMixology/Localizable.xcstrings`; `ios/scripts/sync-strings.sh` refreshes it after a CLI build). Android uses `strings.xml`. Not yet localisable on iOS: strings produced by the core package (badge labels, glass/method/difficulty names, substitution notes assembled from English fragments) — see Future Improvements.
- **Performance budget:** matching a 30-item cabinet against the full catalog (~158 recipes) must stay well under 100 ms (measured ~8 ms on a Mac debug build; a unit test enforces it).

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

Build order: iOS first, end-to-end to a complete MVP, then port to Android.

## Full design docs

The Obsidian vault (`Project Ideas/Dev Project Ideas/Norse Mixology/`) has the complete picture: `Overview.md`, `Data Model.md` (full taxonomy tables), `Design System.md`, `Frontend - iOS.md`, `Frontend - Android.md`, `Deployment.md`, `Future Improvements.md`, and per-phase checklists under `Phases/`.
