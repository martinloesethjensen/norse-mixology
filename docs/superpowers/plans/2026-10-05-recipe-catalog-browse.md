# Recipe Catalog Browse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user browse the whole recipe catalog with search and filters, see exactly what each recipe is missing, and add a missing ingredient to the cabinet from the recipe screen.

**Architecture:** Pure logic lives in the `NorseMixologyCore` SPM package (unit-tested with `swift test`): `CatalogAvailability` evaluates every recipe against the cabinet by reusing the matching engine's own `resolve`, `RecipeFilter` does search/filtering, `GroupedAvailability` buckets entries into Ready / Missing 1 / Missing 2 / Missing 3+. The app target gets a Can make | All recipes toggle on the Recipes tab, a filter sheet, a compact catalog list, and an add button on missing ingredient rows. The matching engine's behaviour and public interface do not change.

**Tech Stack:** Swift 5.9, SwiftUI (iOS 17), SwiftData, XCTest, xcodegen.

**Spec:** `docs/superpowers/specs/2026-10-04-recipe-catalog-browse-design.md`

## Global Constraints

- Min iOS stays **17.0**; no new dependencies.
- iOS only — do not touch `android/`.
- **Additive only:** in `MatchingService.swift` the only allowed change is `private` → `internal` on `Resolution` and `resolve(...)`. No other engine edits.
- Invariant: a recipe is **Ready** in All recipes **iff** it appears in Can make.
- `@Observable` view models only — no Combine, no `ObservableObject`.
- Colours and font sizes only via `DesignTokens` / `.dsText(...)` — no literals in views.
- Structured logging only (`AppLog`, `os.Logger`) — no `print`.
- All new UI strings must end up in `ios/NorseMixology/Localizable.xcstrings` (run `ios/scripts/sync-strings.sh` after a CLI build).
- Touch targets ≥ 44 pt; Reduce Motion respected; VoiceOver labels on icon-only buttons.
- New app-target Swift files are registered by running `xcodegen generate` in `ios/` (the only expected pbxproj churn besides new files is ID churn on `FloatingIcon.swift`). Verify every new file appears in a `SwiftCompile` line of the build log.
- Performance: evaluating + filtering 158 recipes against a 30-item cabinet stays **< 100 ms**.

**Commands used throughout:**
- Core tests: `cd ios/Packages/NorseMixologyCore && swift test` (baseline: 153 tests, 0 failures). Filter with `swift test --filter <TestClass>`.
- App build: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

---

## File Structure

**Core package** (`ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/`)
- Modify `Services/MatchingService.swift` — visibility of `Resolution` and `resolve` only.
- Create `Models/CatalogEntry.swift` — `CatalogEntry`, `AvailabilityTier`.
- Create `Services/CatalogAvailability.swift` — `CatalogAvailability.evaluate`.
- Create `Models/RecipeFilter.swift` — `RecipeFilter` (+ `Strength`, `Criterion`), `RecipeFilterOptions`, `GroupedMatchResults.filtered`.
- Modify `Services/TasteRanking.swift` — extract `isActive(_:)` and generic `sorted(_:toward:flavor:)`.
- Create `Models/GroupedAvailability.swift` — `GroupedAvailability`, `RecipeBrowseState`.

**Core tests** (`ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/`)
- Create `CatalogAvailabilityTests.swift`, `RecipeFilterTests.swift`, `GroupedAvailabilityTests.swift`.
- Modify `HardeningTests.swift` — performance budget for evaluate + filter.

**App** (`ios/NorseMixology/`)
- Modify `NorseMixologyApp.swift`, `ContentView.swift`, `Cabinet/CabinetView.swift` — one shared `CabinetViewModel`.
- Modify `Recipes/RecipeBrowserViewModel.swift` — browse state, entries, filtered groups, selection.
- Modify `Recipes/RecipeBrowserView.swift` — toggle, search, filter button, mode switching.
- Create `Recipes/BrowseHeader.swift` — segmented picker + active-filter chips.
- Create `Recipes/FlowLayout.swift` — wrapping layout for chips.
- Create `Recipes/RecipeFilterSheet.swift` — full filter UI.
- Create `Recipes/CatalogList.swift` and `Recipes/CatalogRowView.swift` — All recipes list.
- Create `Recipes/NoMatchingRecipesView.swift` — filtered-empty state.
- Modify `Recipes/RecipeDetailView.swift`, `Recipes/IngredientRowView.swift` — `CatalogEntry` init, add-to-cabinet button.

**Docs**
- Modify `NORSE_MIXOLOGY_BUILD.md` — new "Recipe catalog browse (iOS)" section.
- Modify the spec — amendments discovered during planning (Task 8).

---

### Task 1: `CatalogAvailability` — what each recipe is missing

**Files:**
- Modify: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/MatchingService.swift` (the `private enum Resolution` declaration near line 57 and `private static func resolve(` near line 136)
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/CatalogEntry.swift`
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/CatalogAvailability.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogAvailabilityTests.swift`
- Modify: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/HardeningTests.swift`

**Interfaces:**
- Consumes: `MatchingService.match(cabinet:recipes:index:prefs:)`, `MatchingService.resolve(requiredStyle:cabinetByStyleId:cabinetByFamilyId:stylesById:curatedTable:prefs:)` (made internal here), `RoleDerivation.role(for:style:in:index:)`, `CuratedSubstitutions.table(index:)`, `SubstitutionNote.generate(required:substitute:)`, `SubstitutionNote.ratioHint(role:required:substitute:)`.
- Produces:
  - `public enum AvailabilityTier: CaseIterable, Sendable { case ready, missing1, missing2, missing3Plus }`
  - `public struct CatalogEntry: Identifiable, Equatable, Sendable { id: UUID; recipe: Recipe; match: RecipeMatchResult?; substitutions: [SubstitutionDetail]; missing: [IngredientStyle]; tier: AvailabilityTier; init(recipe:match:substitutions:missing:) }`
  - `CatalogAvailability.evaluate(recipes:cabinet:index:prefs:) -> [CatalogEntry]` and `evaluate(recipes:cabinet:taxonomyCategories:prefs:)` — one entry per recipe, in catalog order.

- [ ] **Step 1: Write the failing tests**

Create `CatalogAvailabilityTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

/// Recipe Catalog Browse spec §2/§4: every catalog recipe evaluated against the
/// cabinet, with "Ready" defined by the engine's own results.
final class CatalogAvailabilityTests: XCTestCase {
    private var index: TaxonomyIndex!
    private var recipes: [Recipe]!

    override func setUpWithError() throws {
        index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
    }

    private func style(_ name: String) throws -> IngredientStyle {
        try XCTUnwrap(index.stylesById.values.first { $0.name == name }, "no style named \(name)")
    }

    private func item(for style: IngredientStyle) -> CabinetItem {
        CabinetItem(ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                    displayName: style.name, brand: nil, style: style.name,
                    family: index.familyName(for: style), category: index.categoryName(for: style),
                    flavorProfile: style.flavorProfile)
    }

    private func cabinet(_ names: String...) throws -> [CabinetItem] {
        try names.map { item(for: try style($0)) }
    }

    private func entry(_ name: String, in entries: [CatalogEntry]) throws -> CatalogEntry {
        try XCTUnwrap(entries.first { $0.recipe.name == name }, "no entry for \(name)")
    }

    // MARK: - Parity with the engine

    func testReadyEntriesAreExactlyTheEngineResultsForSeveralCabinets() throws {
        let first30 = index.stylesById.values.sorted { $0.name < $1.name }.prefix(30).map { item(for: $0) }
        let cabinets: [[CabinetItem]] = [
            [],
            try cabinet("London Dry Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth"),
            try cabinet("London Dry Gin", "Lime Juice", "Raspberry Liqueur"),
            try cabinet("Rye Whiskey", "Angostura Bitters"),
            Array(first30),
        ]
        for cabinet in cabinets {
            let engineIds = Set(MatchingService.match(cabinet: cabinet, recipes: recipes, index: index).map(\.id))
            let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: cabinet, index: index)
            XCTAssertEqual(Set(entries.filter { $0.tier == .ready }.map(\.id)), engineIds)
            for entry in entries {
                XCTAssertEqual(entry.match != nil, engineIds.contains(entry.id))
                if entry.match != nil { XCTAssertTrue(entry.missing.isEmpty, "\(entry.recipe.name) is ready but lists missing") }
            }
        }
    }

    func testEveryCatalogRecipeGetsOneEntryInCatalogOrder() throws {
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: try cabinet("London Dry Gin"), index: index)
        XCTAssertEqual(entries.map(\.id), recipes.map(\.id))
    }

    // MARK: - Missing ingredients

    func testLastWordIsMissingOnlyGreenChartreuse() throws {
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("London Dry Gin", "Lime Juice", "Raspberry Liqueur"), index: index)
        let lastWord = try entry("Last Word", in: entries)
        XCTAssertNil(lastWord.match)
        XCTAssertEqual(lastWord.missing.map(\.name), ["Green Chartreuse"])
        XCTAssertEqual(lastWord.tier, .missing1)
    }

    func testAddingTheMissingIngredientMovesTheRecipeToReady() throws {
        let entries = CatalogAvailability.evaluate(
            recipes: recipes,
            cabinet: try cabinet("London Dry Gin", "Lime Juice", "Raspberry Liqueur", "Green Chartreuse"),
            index: index)
        let lastWord = try entry("Last Word", in: entries)
        XCTAssertNotNil(lastWord.match)
        XCTAssertTrue(lastWord.missing.isEmpty)
        XCTAssertEqual(lastWord.tier, .ready)
    }

    func testGarnishesAndOptionalIngredientsAreNeverMissing() throws {
        // Negroni = gin + sweet vermouth + Bitter Aperitif + orange wheel (garnish).
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("London Dry Gin", "Sweet/Rosso Vermouth"), index: index)
        XCTAssertEqual(try entry("Negroni", in: entries).missing.map(\.name), ["Bitter Aperitif"])
        for entry in entries {
            for missing in entry.missing {
                let ingredient = try XCTUnwrap(entry.recipe.ingredients.first { $0.ingredientStyleId == missing.id })
                XCTAssertFalse(ingredient.isOptional, "\(entry.recipe.name): optional \(missing.name) listed as missing")
                XCTAssertNotEqual(RoleDerivation.role(for: ingredient, style: missing, in: entry.recipe, index: index), .garnish)
            }
        }
    }

    func testMissingIsInRecipeOrder() throws {
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)
        for entry in entries {
            let recipeOrder = entry.recipe.ingredients.map(\.ingredientStyleId)
            let positions = entry.missing.map { style in recipeOrder.firstIndex(of: style.id)! }
            XCTAssertEqual(positions, positions.sorted(), entry.recipe.name)
        }
    }

    func testSubstitutionsAreReportedOnRecipesThatAreNotMakeableYet() throws {
        // Old Fashioned = Bourbon + Demerara Syrup + Angostura + orange wheel. Rye stands in for Bourbon.
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("Rye Whiskey", "Angostura Bitters"), index: index)
        let oldFashioned = try entry("Old Fashioned", in: entries)
        XCTAssertNil(oldFashioned.match)
        XCTAssertEqual(oldFashioned.missing.map(\.name), ["Demerara Syrup"])
        let sub = try XCTUnwrap(oldFashioned.substitutions.first { $0.required.name == "Bourbon" })
        XCTAssertEqual(sub.substitute.name, "Rye Whiskey")
        XCTAssertFalse(sub.note.isEmpty)
    }

    func testDuplicateStyleInARecipeIsListedOnce() throws {
        let gin = try style("London Dry Gin")
        let line = RecipeIngredient(ingredientStyleId: gin.id, amount: "30ml", preparation: nil, isOptional: false, substituteNotes: nil)
        let doubleGin = Recipe(id: UUID(), name: "Double Gin", description: "", glassType: .rocks, method: .stir,
                               ingredients: [line, line], steps: [], flavorProfile: gin.flavorProfile, tags: [],
                               difficulty: .easy, imageURL: nil)
        let entries = CatalogAvailability.evaluate(recipes: [doubleGin], cabinet: try cabinet("Lime Juice"), index: index)
        XCTAssertEqual(entries.first?.missing.map(\.name), ["London Dry Gin"])
    }

    // MARK: - Edge cases

    func testEmptyCabinetListsEveryRequiredIngredientAsMissingAndDropsNothing() throws {
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [], index: index)
        XCTAssertEqual(entries.count, recipes.count)
        XCTAssertTrue(entries.allSatisfy { $0.match == nil })
        XCTAssertTrue(entries.allSatisfy { $0.substitutions.isEmpty })
        let negroni = try entry("Negroni", in: entries)
        XCTAssertEqual(negroni.missing.map(\.name), ["London Dry Gin", "Sweet/Rosso Vermouth", "Bitter Aperitif"])
    }

    func testGhostCabinetItemNeverActsAsASubstitute() throws {
        let londonDry = try style("London Dry Gin")
        let ghostGin = CabinetItem(ingredientStyleId: UUID(), ingredientFamilyId: londonDry.familyId, categoryId: londonDry.categoryId,
                                   displayName: "Discontinued Gin", brand: nil, style: "Discontinued Gin",
                                   family: "Gin", category: "Spirit", flavorProfile: londonDry.flavorProfile)
        let entries = CatalogAvailability.evaluate(
            recipes: recipes, cabinet: try cabinet("Sweet/Rosso Vermouth", "Bitter Aperitif") + [ghostGin], index: index)
        let negroni = try entry("Negroni", in: entries)
        XCTAssertEqual(negroni.missing.map(\.name), ["London Dry Gin"])
        XCTAssertTrue(negroni.substitutions.isEmpty)
    }

    func testRecipeIngredientMissingFromTheIndexDoesNotCrash() throws {
        let gin = try style("London Dry Gin")
        let entries = CatalogAvailability.evaluate(recipes: recipes, cabinet: [item(for: gin)], index: TaxonomyIndex(categories: []))
        XCTAssertEqual(entries.count, recipes.count)
        XCTAssertTrue(entries.allSatisfy { $0.missing.isEmpty })
    }

    func testTierFollowsMissingCount() throws {
        let recipe = recipes[0]
        let a = try style("London Dry Gin"), b = try style("Lime Juice"), c = try style("Green Chartreuse")
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: [a]).tier, .missing1)
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: [a, b]).tier, .missing2)
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: [a, b, c]).tier, .missing3Plus)
        // Invariant-guard case: unmatched with nothing missing is never Ready.
        XCTAssertEqual(CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: []).tier, .missing1)
    }
}
```

Append to `HardeningTests.swift`, inside the class, after `testMatchingA30ItemCabinetAgainstTheFullCatalogIsWellUnder100ms`:

```swift
    func testEvaluatingTheWholeCatalogForA30ItemCabinetIsWellUnder100ms() throws {
        let categories = try IngredientTaxonomy.loadCategories(from: bundledData("taxonomy"))
        let recipes = try IngredientTaxonomy.loadRecipes(from: bundledData("recipes"))
        let index = TaxonomyIndex(categories: categories)

        let cabinet = index.stylesById.values.sorted { $0.name < $1.name }.prefix(30).map { style in
            CabinetItem(
                ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                displayName: style.name, brand: nil, style: style.name,
                family: index.familyName(for: style), category: index.categoryName(for: style),
                flavorProfile: style.flavorProfile
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let entries = CatalogAvailability.evaluate(recipes: Array(recipes), cabinet: Array(cabinet), index: index)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(entries.count, recipes.count)
        XCTAssertLessThan(elapsed, 0.1, "evaluated \(recipes.count) recipes in \(Int(elapsed * 1000))ms")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter CatalogAvailabilityTests`
Expected: build FAILS with `cannot find 'CatalogAvailability' in scope` / `cannot find 'CatalogEntry' in scope`.

- [ ] **Step 3: Open up `resolve` (the only engine change)**

In `MatchingService.swift` change exactly two declarations:

```swift
    enum Resolution {   // was: private enum Resolution
```

```swift
    static func resolve(   // was: private static func resolve(
```

Add one doc line above `static func resolve(`:

```swift
    /// Internal (not private) so `CatalogAvailability` reuses the exact same per-ingredient rule.
```

- [ ] **Step 4: Create `Models/CatalogEntry.swift`**

```swift
import Foundation

/// How far a catalog recipe is from makeable with the current cabinet.
public enum AvailabilityTier: CaseIterable, Sendable {
    case ready, missing1, missing2, missing3Plus
}

/// One catalog recipe evaluated against the cabinet (Recipe Catalog Browse spec §2).
public struct CatalogEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { recipe.id }
    public let recipe: Recipe
    /// The engine's own result — non-nil exactly when the recipe appears in "Can make".
    public let match: RecipeMatchResult?
    /// Ingredients a cabinet item stands in for — reported even when the recipe
    /// isn't makeable yet, so the detail screen can show them as substituted.
    public let substitutions: [SubstitutionDetail]
    /// Required ingredients nothing in the cabinet can cover, in recipe order, no duplicates.
    public let missing: [IngredientStyle]

    public init(recipe: Recipe, match: RecipeMatchResult?, substitutions: [SubstitutionDetail], missing: [IngredientStyle]) {
        self.recipe = recipe
        self.match = match
        self.substitutions = substitutions
        self.missing = missing
    }

    public var tier: AvailabilityTier {
        if match != nil { return .ready }
        switch missing.count {
        case 0, 1: return .missing1 // 0 only via CatalogAvailability's invariant guard — never Ready
        case 2: return .missing2
        default: return .missing3Plus
        }
    }
}
```

- [ ] **Step 5: Create `Services/CatalogAvailability.swift`**

```swift
import Foundation

/// Evaluates every catalog recipe against the cabinet — the All recipes view.
/// "Ready" is the matching engine's own result; for everything else the
/// engine's per-ingredient `resolve` decides what is missing, so the two views
/// can never disagree. Additive only: `MatchingService` is not changed.
public enum CatalogAvailability {
    public static func evaluate(
        recipes: [Recipe],
        cabinet: [CabinetItem],
        taxonomyCategories: [IngredientCategory],
        prefs: MatchPreferences = .default
    ) -> [CatalogEntry] {
        evaluate(recipes: recipes, cabinet: cabinet, index: TaxonomyIndex(categories: taxonomyCategories), prefs: prefs)
    }

    public static func evaluate(
        recipes: [Recipe],
        cabinet: [CabinetItem],
        index: TaxonomyIndex,
        prefs: MatchPreferences = .default
    ) -> [CatalogEntry] {
        let matches = MatchingService.match(cabinet: cabinet, recipes: recipes, index: index, prefs: prefs)
        let matchById = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The same lookups `MatchingService.match` builds — duplicated rather than
        // refactored out so the engine itself stays untouched.
        let cabinetByStyleId = Dictionary(cabinet.map { ($0.ingredientStyleId, $0) }, uniquingKeysWith: { first, _ in first })
        var cabinetByFamilyId: [UUID: [CabinetItem]] = [:]
        for item in cabinet {
            cabinetByFamilyId[item.ingredientFamilyId, default: []].append(item)
        }
        let curatedTable = CuratedSubstitutions.table(index: index)

        return recipes.map { recipe in
            if let match = matchById[recipe.id] {
                return CatalogEntry(recipe: recipe, match: match, substitutions: match.substitutions, missing: [])
            }

            var substitutions: [SubstitutionDetail] = []
            var missing: [IngredientStyle] = []
            for ingredient in recipe.ingredients {
                guard let requiredStyle = index.stylesById[ingredient.ingredientStyleId] else {
                    continue // dangling reference — skipped exactly as the engine does
                }
                let role = RoleDerivation.role(for: ingredient, style: requiredStyle, in: recipe, index: index)
                let isSoft = ingredient.isOptional || role == .garnish

                let resolution = MatchingService.resolve(
                    requiredStyle: requiredStyle,
                    cabinetByStyleId: cabinetByStyleId,
                    cabinetByFamilyId: cabinetByFamilyId,
                    stylesById: index.stylesById,
                    curatedTable: curatedTable,
                    prefs: prefs
                )
                switch resolution {
                case .unresolved:
                    if !isSoft, !missing.contains(where: { $0.id == requiredStyle.id }) {
                        missing.append(requiredStyle)
                    }
                case .resolved(let quality, let substituteStyle):
                    if let substituteStyle, substituteStyle.id != requiredStyle.id {
                        substitutions.append(SubstitutionDetail(
                            required: requiredStyle,
                            substitute: substituteStyle,
                            similarityScore: quality,
                            note: SubstitutionNote.generate(required: requiredStyle, substitute: substituteStyle),
                            ratioHint: SubstitutionNote.ratioHint(role: role, required: requiredStyle, substitute: substituteStyle)
                        ))
                    }
                }
            }

            // The engine returns nothing for an empty cabinet, so an unmatched
            // recipe with nothing missing is only expected then.
            if missing.isEmpty, !cabinet.isEmpty {
                AppLog.catalog.fault("Recipe \(recipe.name, privacy: .public) is not makeable but has nothing missing")
            }
            return CatalogEntry(recipe: recipe, match: nil, substitutions: substitutions, missing: missing)
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter 'CatalogAvailabilityTests|HardeningTests'`
Expected: PASS (all `CatalogAvailabilityTests` + `HardeningTests`, including the new budget test).

If `testLastWordIsMissingOnlyGreenChartreuse` fails because a substitute covers Green Chartreuse, print `lastWord.substitutions` and pick another herbal-liqueur recipe from `Alaska`, `Naked and Famous`, `Widow's Kiss` — do **not** change the engine.

- [ ] **Step 7: Run the full suite (engine regression check)**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: `Executed 166 tests, with 0 failures` (153 baseline + 12 + 1).

- [ ] **Step 8: Commit**

```bash
git add ios/Packages/NorseMixologyCore
git commit -m "Core: CatalogAvailability — evaluate every recipe and list what's missing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `RecipeFilter` — search and filters

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RecipeFilter.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RecipeFilterTests.swift`

**Interfaces:**
- Consumes: `Recipe`, `TaxonomyIndex`, `RoleDerivation.role(for:style:in:index:)`, `GroupedMatchResults(results:)`, `GlassType`, `Method`, `Difficulty` (all existing).
- Produces:
  - `public struct RecipeFilter: Equatable, Sendable` with `var query: String`, `private(set) var criteria: [Criterion]`, `isEmpty`, `trimmedQuery`, `contains(_:)`, `toggle(_:)`, `remove(_:)`, `clear()`, `matches(_ recipe: Recipe, index: TaxonomyIndex) -> Bool`, `static let styleTags: [String]`, `static func baseFamilyIds(of: Recipe, index: TaxonomyIndex) -> Set<UUID>`.
  - `public enum RecipeFilter.Strength: String, CaseIterable, Sendable { case noABV, lowABV, regular }` with `init(recipe:)`, `displayName`.
  - `public enum RecipeFilter.Criterion: Hashable, Sendable { case tag(String), strength(Strength), baseFamily(UUID), glass(GlassType), method(Method), difficulty(Difficulty) }`.
  - `public struct RecipeFilterOptions: Equatable, Sendable { tags: [String]; baseFamilies: [FamilyOption]; glassTypes: [GlassType]; methods: [Method]; difficulties: [Difficulty]; init(recipes:index:); static let empty }`, `public struct FamilyOption: Hashable, Sendable { id: UUID; name: String }`.
  - `extension GroupedMatchResults { func filtered(by: RecipeFilter, index: TaxonomyIndex) -> GroupedMatchResults }`.

- [ ] **Step 1: Write the failing tests**

Create `RecipeFilterTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

final class RecipeFilterTests: XCTestCase {
    private var index: TaxonomyIndex!
    private var recipes: [Recipe]!

    override func setUpWithError() throws {
        index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
    }

    private func names(_ filter: RecipeFilter) -> Set<String> {
        Set(recipes.filter { filter.matches($0, index: index) }.map(\.name))
    }

    private func filter(query: String = "", _ criteria: RecipeFilter.Criterion...) -> RecipeFilter {
        var filter = RecipeFilter()
        filter.query = query
        criteria.forEach { filter.toggle($0) }
        return filter
    }

    private func familyId(_ name: String) throws -> UUID {
        try XCTUnwrap(index.familyNamesById.first { $0.value == name }?.key, "no family \(name)")
    }

    // MARK: - Query

    func testEmptyAndWhitespaceQueriesMatchEverything() {
        XCTAssertEqual(names(filter()).count, recipes.count)
        XCTAssertEqual(names(filter(query: "  \n\t ")).count, recipes.count)
        XCTAssertTrue(filter(query: "   ").isEmpty)
    }

    func testQueryMatchesRecipeNameCaseInsensitively() {
        XCTAssertTrue(names(filter(query: "negroni")).contains("Negroni"))
    }

    func testQueryIgnoresDiacritics() {
        XCTAssertTrue(names(filter(query: "pina colada")).contains("Piña Colada"))
        XCTAssertTrue(names(filter(query: "vieux carre")).contains("Vieux Carré"))
    }

    func testQueryMatchesIngredientStyleAndFamilyNames() {
        XCTAssertTrue(names(filter(query: "chartreuse")).contains("Last Word"), "style name")
        XCTAssertTrue(names(filter(query: "curacao")).isSuperset(of: names(filter(query: "Orange Curaçao"))), "diacritics on style")
        let byFamily = names(filter(query: "vermouth"))
        XCTAssertTrue(byFamily.contains("Negroni"), "family name")
    }

    func testOddQueriesNeverCrashAndMatchNothing() {
        XCTAssertTrue(names(filter(query: "🍸🦄")).isEmpty)
        XCTAssertTrue(names(filter(query: String(repeating: "x", count: 1_000))).isEmpty)
        XCTAssertTrue(names(filter(query: "كوكتيل")).isEmpty)
    }

    // MARK: - Criteria

    func testStrengthComesFromAbvTags() throws {
        let noAbv = try XCTUnwrap(recipes.first { $0.tags.contains("no-abv") })
        let lowAbv = try XCTUnwrap(recipes.first { $0.tags.contains("low-abv") })
        let negroni = try XCTUnwrap(recipes.first { $0.name == "Negroni" })
        XCTAssertEqual(RecipeFilter.Strength(recipe: noAbv), .noABV)
        XCTAssertEqual(RecipeFilter.Strength(recipe: lowAbv), .lowABV)
        XCTAssertEqual(RecipeFilter.Strength(recipe: negroni), .regular)
        XCTAssertEqual(names(filter(.strength(.noABV))).count, recipes.filter { $0.tags.contains("no-abv") }.count)
    }

    func testBaseSpiritUsesTheBaseRoleFamily() throws {
        let gin = try familyId("Gin")
        let result = names(filter(.baseFamily(gin)))
        XCTAssertTrue(result.contains("Negroni"))
        XCTAssertFalse(result.contains("Daiquiri"))
        let negroni = try XCTUnwrap(recipes.first { $0.name == "Negroni" })
        XCTAssertEqual(RecipeFilter.baseFamilyIds(of: negroni, index: index), [gin])
    }

    func testValuesOfOneKindCombineWithOr() {
        let sour = names(filter(.tag("sour")))
        let tiki = names(filter(.tag("tiki")))
        XCTAssertEqual(names(filter(.tag("sour"), .tag("tiki"))), sour.union(tiki))
    }

    func testDifferentKindsCombineWithAnd() {
        let sour = names(filter(.tag("sour")))
        let shaken = names(filter(.method(.shake)))
        XCTAssertEqual(names(filter(.tag("sour"), .method(.shake))), sour.intersection(shaken))
    }

    func testQueryAndCriteriaCombineWithAnd() {
        let gin = names(filter(query: "gin"))
        let stirred = names(filter(.method(.stir)))
        XCTAssertEqual(names(filter(query: "gin", .method(.stir))), gin.intersection(stirred))
    }

    func testGlassAndDifficultyFilters() {
        XCTAssertEqual(names(filter(.glass(.coupe))), Set(recipes.filter { $0.glassType == .coupe }.map(\.name)))
        XCTAssertEqual(names(filter(.difficulty(.easy))), Set(recipes.filter { $0.difficulty == .easy }.map(\.name)))
    }

    // MARK: - Editing criteria

    func testToggleAddsThenRemovesAndKeepsInsertionOrder() {
        var filter = RecipeFilter()
        filter.toggle(.tag("sour"))
        filter.toggle(.method(.shake))
        XCTAssertEqual(filter.criteria, [.tag("sour"), .method(.shake)])
        filter.toggle(.tag("sour"))
        XCTAssertEqual(filter.criteria, [.method(.shake)])
        filter.remove(.method(.shake))
        XCTAssertTrue(filter.isEmpty)
    }

    func testClearResetsQueryAndCriteria() {
        var filter = filter(query: "gin", .tag("sour"))
        filter.clear()
        XCTAssertEqual(filter, RecipeFilter())
    }

    // MARK: - Options and grouped results

    func testOptionsOnlyOfferValuesPresentInTheCatalog() {
        let options = RecipeFilterOptions(recipes: recipes, index: index)
        XCTAssertEqual(Set(options.methods), Set(recipes.map(\.method)))
        XCTAssertEqual(options.difficulties, [.easy, .medium, .advanced])
        XCTAssertTrue(options.tags.allSatisfy(RecipeFilter.styleTags.contains))
        XCTAssertTrue(options.baseFamilies.contains { $0.name == "Gin" })
        XCTAssertEqual(options.baseFamilies.map(\.name), options.baseFamilies.map(\.name).sorted())
    }

    func testFilteringGroupedResultsKeepsTiersAndOrder() throws {
        let gin = try XCTUnwrap(index.stylesById.values.first { $0.name == "London Dry Gin" })
        let cabinet = [gin].map { style in
            CabinetItem(ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                        displayName: style.name, brand: nil, style: style.name,
                        family: index.familyName(for: style), category: index.categoryName(for: style),
                        flavorProfile: style.flavorProfile)
        }
        let grouped = GroupedMatchResults(results: MatchingService.match(cabinet: cabinet, recipes: recipes, index: index))
        XCTAssertEqual(grouped.filtered(by: RecipeFilter(), index: index), grouped)
        let filtered = grouped.filtered(by: filter(.method(.stir)), index: index)
        XCTAssertEqual(filtered.perfect.map(\.id), grouped.perfect.filter { $0.recipe.method == .stir }.map(\.id))
        XCTAssertEqual(filtered.almost.map(\.id), grouped.almost.filter { $0.recipe.method == .stir }.map(\.id))
        XCTAssertEqual(filtered.exploring.map(\.id), grouped.exploring.filter { $0.recipe.method == .stir }.map(\.id))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RecipeFilterTests`
Expected: build FAILS with `cannot find type 'RecipeFilter' in scope`.

- [ ] **Step 3: Create `Models/RecipeFilter.swift`**

```swift
import Foundation

/// Search + filter criteria for the Recipes tab (Recipe Catalog Browse spec §2).
/// Different kinds of criterion combine with AND; several values of one kind with OR.
public struct RecipeFilter: Equatable, Sendable {
    public enum Strength: String, CaseIterable, Sendable {
        case noABV, lowABV, regular

        public init(recipe: Recipe) {
            if recipe.tags.contains("no-abv") {
                self = .noABV
            } else if recipe.tags.contains("low-abv") {
                self = .lowABV
            } else {
                self = .regular
            }
        }

        public var displayName: String {
            switch self {
            case .noABV: return "No alcohol"
            case .lowABV: return "Low alcohol"
            case .regular: return "Regular"
            }
        }
    }

    /// One removable filter value — what a chip shows and what the filter sheet toggles.
    public enum Criterion: Hashable, Sendable {
        case tag(String)
        case strength(Strength)
        case baseFamily(UUID)
        case glass(GlassType)
        case method(Method)
        case difficulty(Difficulty)
    }

    /// Curated style tags offered in the filter UI; other catalog tags are ignored.
    public static let styleTags = ["sour", "tall", "spirit-forward", "refreshing", "tiki", "creamy", "sparkling", "bitter", "smoky", "dessert"]

    public var query: String = ""
    /// In the order the user added them, so chips don't jump around.
    public private(set) var criteria: [Criterion] = []

    public init() {}

    public var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isEmpty: Bool { trimmedQuery.isEmpty && criteria.isEmpty }

    public func contains(_ criterion: Criterion) -> Bool { criteria.contains(criterion) }

    public mutating func toggle(_ criterion: Criterion) {
        if let position = criteria.firstIndex(of: criterion) {
            criteria.remove(at: position)
        } else {
            criteria.append(criterion)
        }
    }

    public mutating func remove(_ criterion: Criterion) {
        criteria.removeAll { $0 == criterion }
    }

    public mutating func clear() {
        query = ""
        criteria = []
    }

    public func matches(_ recipe: Recipe, index: TaxonomyIndex) -> Bool {
        matchesQuery(recipe, index: index) && matchesCriteria(recipe, index: index)
    }

    /// Families of the ingredient(s) `RoleDerivation` treats as the recipe's base.
    public static func baseFamilyIds(of recipe: Recipe, index: TaxonomyIndex) -> Set<UUID> {
        Set(recipe.ingredients.compactMap { ingredient -> UUID? in
            guard let style = index.stylesById[ingredient.ingredientStyleId],
                  RoleDerivation.role(for: ingredient, style: style, in: recipe, index: index) == .base else { return nil }
            return style.familyId
        })
    }

    /// Case- and diacritic-insensitive substring match on the recipe name, then
    /// on each ingredient's style and family name.
    private func matchesQuery(_ recipe: Recipe, index: TaxonomyIndex) -> Bool {
        let query = trimmedQuery
        guard !query.isEmpty else { return true }
        if recipe.name.localizedStandardContains(query) { return true }
        return recipe.ingredients.contains { ingredient in
            guard let style = index.stylesById[ingredient.ingredientStyleId] else { return false }
            return style.name.localizedStandardContains(query) || index.familyName(for: style).localizedStandardContains(query)
        }
    }

    private func matchesCriteria(_ recipe: Recipe, index: TaxonomyIndex) -> Bool {
        guard !criteria.isEmpty else { return true }
        var tags: Set<String> = []
        var strengths: Set<Strength> = []
        var families: Set<UUID> = []
        var glasses: Set<GlassType> = []
        var methods: Set<Method> = []
        var difficulties: Set<Difficulty> = []
        for criterion in criteria {
            switch criterion {
            case .tag(let tag): tags.insert(tag)
            case .strength(let strength): strengths.insert(strength)
            case .baseFamily(let id): families.insert(id)
            case .glass(let glass): glasses.insert(glass)
            case .method(let method): methods.insert(method)
            case .difficulty(let difficulty): difficulties.insert(difficulty)
            }
        }
        if !tags.isEmpty, tags.isDisjoint(with: recipe.tags) { return false }
        if !strengths.isEmpty, !strengths.contains(Strength(recipe: recipe)) { return false }
        if !families.isEmpty, families.isDisjoint(with: Self.baseFamilyIds(of: recipe, index: index)) { return false }
        if !glasses.isEmpty, !glasses.contains(recipe.glassType) { return false }
        if !methods.isEmpty, !methods.contains(recipe.method) { return false }
        if !difficulties.isEmpty, !difficulties.contains(recipe.difficulty) { return false }
        return true
    }
}

public struct FamilyOption: Hashable, Sendable {
    public let id: UUID
    public let name: String
}

/// The values the filter sheet offers — only ones present in the loaded catalog,
/// so new catalog values appear without an app update.
public struct RecipeFilterOptions: Equatable, Sendable {
    public let tags: [String]
    public let baseFamilies: [FamilyOption]
    public let glassTypes: [GlassType]
    public let methods: [Method]
    public let difficulties: [Difficulty]

    public static let empty = RecipeFilterOptions(recipes: [], index: TaxonomyIndex(categories: []))

    public init(recipes: [Recipe], index: TaxonomyIndex) {
        let presentTags = Set(recipes.flatMap(\.tags))
        tags = RecipeFilter.styleTags.filter(presentTags.contains)

        let familyIds = recipes.reduce(into: Set<UUID>()) { $0.formUnion(RecipeFilter.baseFamilyIds(of: $1, index: index)) }
        baseFamilies = familyIds
            .compactMap { id in index.familyNamesById[id].map { FamilyOption(id: id, name: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        glassTypes = Set(recipes.map(\.glassType)).sorted { $0.displayName < $1.displayName }
        methods = Set(recipes.map(\.method)).sorted { $0.displayName < $1.displayName }
        let presentDifficulties = Set(recipes.map(\.difficulty))
        difficulties = [Difficulty.easy, .medium, .advanced].filter(presentDifficulties.contains)
    }
}

public extension GroupedMatchResults {
    /// The Can make view filtered without re-running the engine: tiers and the
    /// order within them are kept.
    func filtered(by filter: RecipeFilter, index: TaxonomyIndex) -> GroupedMatchResults {
        guard !filter.isEmpty else { return self }
        let keep = { (result: RecipeMatchResult) in filter.matches(result.recipe, index: index) }
        return GroupedMatchResults(results: perfect.filter(keep) + almost.filter(keep) + exploring.filter(keep))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RecipeFilterTests`
Expected: PASS (15 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/NorseMixologyCore
git commit -m "Core: RecipeFilter — search by recipe/ingredient name and filter by strength, base, style, glass, method, difficulty

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `GroupedAvailability` and `RecipeBrowseState`

**Files:**
- Modify: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/TasteRanking.swift`
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/GroupedAvailability.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/GroupedAvailabilityTests.swift`

**Interfaces:**
- Consumes: `CatalogEntry`, `AvailabilityTier` (Task 1); `RecipeFilter` (Task 2); `UserTasteProfile`, `TasteRanking.similarity` (existing).
- Produces:
  - `TasteRanking.isActive(_ profile: UserTasteProfile) -> Bool`, `TasteRanking.sorted<T>(_ items: [T], toward: UserTasteProfile, flavor: (T) -> FlavorProfile) -> [T]` (stable; no-op when inactive).
  - `public struct GroupedAvailability: Equatable, Sendable { ready, missing1, missing2, missing3Plus: [CatalogEntry]; init(entries:profile:); isEmpty; entries(in: AvailabilityTier) -> [CatalogEntry]; allIds: [UUID]; filtered(by: RecipeFilter, index: TaxonomyIndex) -> GroupedAvailability; static let empty }`.
  - `public struct RecipeBrowseState: Equatable, Sendable { enum Mode: String, CaseIterable { canMake, all }; var mode: Mode; var filter: RecipeFilter; init(mode:filter:) }`.

- [ ] **Step 1: Write the failing tests**

Create `GroupedAvailabilityTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

final class GroupedAvailabilityTests: XCTestCase {
    private let style = IngredientStyle(
        id: UUID(), name: "Thing", familyId: UUID(), categoryId: UUID(), exampleBrands: [],
        flavorProfile: FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0),
        abvMin: 0, abvMax: 0)

    private func recipe(_ name: String, sweetness: Double = 0.5, bitterness: Double = 0.5) -> Recipe {
        Recipe(id: UUID(), name: name, description: "", glassType: .rocks, method: .stir, ingredients: [], steps: [],
               flavorProfile: FlavorProfile(sweetness: sweetness, bitterness: bitterness, smokiness: 0.5, citrus: 0.5,
                                            floral: 0, spice: 0, herbal: 0.5, fruity: 0, oaky: 0, abv: 20),
               tags: [], difficulty: .easy, imageURL: nil)
    }

    private func ready(_ recipe: Recipe, exact: Bool = true, score: Double = 1) -> CatalogEntry {
        CatalogEntry(recipe: recipe,
                     match: RecipeMatchResult(recipe: recipe, matchScore: score, matchType: exact ? .exact : .partial, substitutions: []),
                     substitutions: [], missing: [])
    }

    private func missing(_ recipe: Recipe, _ count: Int) -> CatalogEntry {
        CatalogEntry(recipe: recipe, match: nil, substitutions: [], missing: Array(repeating: style, count: count))
    }

    func testEntriesLandInTheirTier() {
        let grouped = GroupedAvailability(entries: [
            missing(recipe("C"), 3), ready(recipe("A")), missing(recipe("B"), 1), missing(recipe("D"), 2), missing(recipe("E"), 5),
        ], profile: .neutral)
        XCTAssertEqual(grouped.ready.map(\.recipe.name), ["A"])
        XCTAssertEqual(grouped.missing1.map(\.recipe.name), ["B"])
        XCTAssertEqual(grouped.missing2.map(\.recipe.name), ["D"])
        XCTAssertEqual(grouped.missing3Plus.map(\.recipe.name), ["C", "E"])
        XCTAssertEqual(grouped.entries(in: .missing2).map(\.recipe.name), ["D"])
        XCTAssertEqual(grouped.allIds.count, 5)
    }

    func testNeutralProfileOrdersReadyLikeTheEngineAndMissingByCountThenName() {
        let grouped = GroupedAvailability(entries: [
            ready(recipe("Partial"), exact: false, score: 0.8), ready(recipe("Zed")), ready(recipe("Alpha")),
            missing(recipe("Mojito"), 4), missing(recipe("Aviation"), 3), missing(recipe("Bramble"), 3),
        ], profile: .neutral)
        XCTAssertEqual(grouped.ready.map(\.recipe.name), ["Alpha", "Zed", "Partial"])
        XCTAssertEqual(grouped.missing3Plus.map(\.recipe.name), ["Aviation", "Bramble", "Mojito"])
    }

    func testActiveProfileRanksByTasteWithinEachTier() {
        let sweetTooth = UserTasteProfile(sweetness: 1, bitterness: 0, citrus: 0.5, smokiness: 0.5, herbal: 0.5, hasCompletedOnboarding: true)
        let grouped = GroupedAvailability(entries: [
            missing(recipe("Bitter", sweetness: 0, bitterness: 1), 1),
            missing(recipe("Sweet", sweetness: 1, bitterness: 0), 1),
            ready(recipe("BitterReady", sweetness: 0, bitterness: 1)),
            ready(recipe("SweetReady", sweetness: 1, bitterness: 0)),
        ], profile: sweetTooth)
        XCTAssertEqual(grouped.missing1.map(\.recipe.name), ["Sweet", "Bitter"])
        XCTAssertEqual(grouped.ready.map(\.recipe.name), ["SweetReady", "BitterReady"])
    }

    func testFilteringKeepsTiersAndOrder() throws {
        let index = TaxonomyIndex(categories: [])
        let grouped = GroupedAvailability(entries: [ready(recipe("Gimlet")), missing(recipe("Gin Fizz"), 1), missing(recipe("Mojito"), 1)],
                                          profile: .neutral)
        var filter = RecipeFilter()
        filter.query = "gi"
        let filtered = grouped.filtered(by: filter, index: index)
        XCTAssertEqual(filtered.ready.map(\.recipe.name), ["Gimlet"])
        XCTAssertEqual(filtered.missing1.map(\.recipe.name), ["Gin Fizz"])
        filter.query = "nothing like this"
        XCTAssertTrue(grouped.filtered(by: filter, index: index).isEmpty)
        XCTAssertEqual(grouped.filtered(by: RecipeFilter(), index: index), grouped)
    }

    func testChangingModeKeepsTheFilter() {
        var state = RecipeBrowseState()
        XCTAssertEqual(state.mode, .canMake)
        state.filter.toggle(.tag("sour"))
        state.mode = .all
        XCTAssertEqual(state.filter.criteria, [.tag("sour")])
        XCTAssertEqual(RecipeBrowseState.Mode(rawValue: "all"), .all, "raw values are persisted in @SceneStorage")
    }

    func testTasteRankingNoOpRuleIsShared() {
        XCTAssertFalse(TasteRanking.isActive(.neutral))
        XCTAssertFalse(TasteRanking.isActive(UserTasteProfile(hasCompletedOnboarding: true)), "Skip path")
        XCTAssertTrue(TasteRanking.isActive(UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: true)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter GroupedAvailabilityTests`
Expected: build FAILS with `cannot find 'GroupedAvailability' in scope`.

- [ ] **Step 3: Extract the taste-sorting rule in `TasteRanking.swift`**

Replace the whole `reorder` function with these three functions (behaviour of `reorder` is unchanged; `TasteRankingTests` guard it):

```swift
    /// A neutral (all axes still 0.5) or uncompleted profile never changes any order.
    public static func isActive(_ profile: UserTasteProfile) -> Bool {
        let hasNeutralAxes = profile.sweetness == 0.5 && profile.bitterness == 0.5
            && profile.citrus == 0.5 && profile.smokiness == 0.5 && profile.herbal == 0.5
        return profile.hasCompletedOnboarding && !hasNeutralAxes
    }

    /// Stable sort by taste similarity, most similar first; a no-op for an inactive profile.
    public static func sorted<T>(_ items: [T], toward profile: UserTasteProfile, flavor: (T) -> FlavorProfile) -> [T] {
        guard isActive(profile) else { return items }
        return items.sorted { similarity(profile, to: flavor($0)) > similarity(profile, to: flavor($1)) }
    }

    /// A neutral (all axes still 0.5) or uncompleted profile is a no-op —
    /// the original matchScore-descending order is preserved.
    public static func reorder(_ grouped: GroupedMatchResults, toward profile: UserTasteProfile) -> GroupedMatchResults {
        guard isActive(profile) else { return grouped }
        let byTaste = { (results: [RecipeMatchResult]) in sorted(results, toward: profile) { $0.recipe.flavorProfile } }
        return GroupedMatchResults(results: byTaste(grouped.perfect) + byTaste(grouped.almost) + byTaste(grouped.exploring))
    }
```

- [ ] **Step 4: Create `Models/GroupedAvailability.swift`**

```swift
import Foundation

/// All recipes, bucketed for the All recipes view: Ready / Missing 1 / Missing 2 / Missing 3+.
/// Base order: Ready like the engine (exact first, then score, then name);
/// Missing tiers by missing count, then name. An active taste profile then
/// re-sorts within each tier (stable, so the base order breaks ties).
public struct GroupedAvailability: Equatable, Sendable {
    public let ready: [CatalogEntry]
    public let missing1: [CatalogEntry]
    public let missing2: [CatalogEntry]
    public let missing3Plus: [CatalogEntry]

    public static let empty = GroupedAvailability(entries: [], profile: .neutral)

    public init(entries: [CatalogEntry], profile: UserTasteProfile) {
        func byName(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
            lhs.recipe.name.localizedStandardCompare(rhs.recipe.name) == .orderedAscending
        }
        func readyOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
            let l = lhs.match, r = rhs.match
            if l?.matchType != r?.matchType { return l?.matchType == .exact }
            if l?.matchScore != r?.matchScore { return (l?.matchScore ?? 0) > (r?.matchScore ?? 0) }
            return byName(lhs, rhs)
        }
        func missingOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
            lhs.missing.count != rhs.missing.count ? lhs.missing.count < rhs.missing.count : byName(lhs, rhs)
        }
        func ranked(_ tier: AvailabilityTier, by order: (CatalogEntry, CatalogEntry) -> Bool) -> [CatalogEntry] {
            TasteRanking.sorted(entries.filter { $0.tier == tier }.sorted(by: order), toward: profile) { $0.recipe.flavorProfile }
        }
        self.init(
            ready: ranked(.ready, by: readyOrder),
            missing1: ranked(.missing1, by: missingOrder),
            missing2: ranked(.missing2, by: missingOrder),
            missing3Plus: ranked(.missing3Plus, by: missingOrder)
        )
    }

    private init(ready: [CatalogEntry], missing1: [CatalogEntry], missing2: [CatalogEntry], missing3Plus: [CatalogEntry]) {
        self.ready = ready
        self.missing1 = missing1
        self.missing2 = missing2
        self.missing3Plus = missing3Plus
    }

    public var isEmpty: Bool { ready.isEmpty && missing1.isEmpty && missing2.isEmpty && missing3Plus.isEmpty }

    public var allIds: [UUID] { (ready + missing1 + missing2 + missing3Plus).map(\.id) }

    public func entries(in tier: AvailabilityTier) -> [CatalogEntry] {
        switch tier {
        case .ready: return ready
        case .missing1: return missing1
        case .missing2: return missing2
        case .missing3Plus: return missing3Plus
        }
    }

    /// Keeps tiers and the order within them.
    public func filtered(by filter: RecipeFilter, index: TaxonomyIndex) -> GroupedAvailability {
        guard !filter.isEmpty else { return self }
        let keep = { (entry: CatalogEntry) in filter.matches(entry.recipe, index: index) }
        return GroupedAvailability(ready: ready.filter(keep), missing1: missing1.filter(keep),
                                   missing2: missing2.filter(keep), missing3Plus: missing3Plus.filter(keep))
    }
}

/// What the Recipes tab is showing — pure state so it is unit-testable
/// (the app target has no test target).
public struct RecipeBrowseState: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case canMake, all
    }

    public var mode: Mode
    public var filter: RecipeFilter

    public init(mode: Mode = .canMake, filter: RecipeFilter = RecipeFilter()) {
        self.mode = mode
        self.filter = filter
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter 'GroupedAvailabilityTests|TasteRankingTests'`
Expected: PASS (6 new + all existing `TasteRankingTests`).

- [ ] **Step 6: Full suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: `Executed 187 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/NorseMixologyCore
git commit -m "Core: GroupedAvailability tiers and RecipeBrowseState; share TasteRanking's no-op rule

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: One shared `CabinetViewModel`

The recipe screen will add to the cabinet, so Cabinet and Recipes must share one view model (today `CabinetView` builds its own in `onAppear`).

**Files:**
- Modify: `ios/NorseMixology/NorseMixologyApp.swift`
- Modify: `ios/NorseMixology/Cabinet/CabinetView.swift:15-45` (state, body, onAppear, sheet)
- Modify: `ios/NorseMixology/ContentView.swift` (preview only)

**Interfaces:**
- Produces: `CabinetViewModel` available app-wide via `@Environment(CabinetViewModel.self)`; existing API `items`, `add(_:taxonomyStore:brand:)`, `contains(styleId:)`, `remove(_:)`, `refresh()` unchanged.

- [ ] **Step 1: Create the view model at the app root**

In `NorseMixologyApp.swift`, add a stored property under `favouritesViewModel`:

```swift
    @State private var cabinetViewModel: CabinetViewModel
```

In `init()`, right after the `_favouritesViewModel = ...` line:

```swift
            _cabinetViewModel = State(initialValue: CabinetViewModel(modelContext: container.mainContext))
```

In `body`, after `.environment(favouritesViewModel)`:

```swift
                .environment(cabinetViewModel)
```

Update the comment above the container creation to: `// so the app-wide FavouritesViewModel and CabinetViewModel can share its main context.`

- [ ] **Step 2: Use it in `CabinetView`**

Replace `@State private var viewModel: CabinetViewModel?` with:

```swift
    @Environment(CabinetViewModel.self) private var viewModel
```

Replace the `Group { if let viewModel { ... } else { ProgressView() } }` block in `body` with:

```swift
            content(viewModel: viewModel)
```

Replace the `.onAppear { if viewModel == nil { viewModel = CabinetViewModel(modelContext: modelContext) } }` modifier with:

```swift
        .onAppear { viewModel.refresh() }
```

Replace the sheet body `if let viewModel { AddIngredientView(...) }` with:

```swift
            AddIngredientView(cabinetViewModel: viewModel, taxonomyStore: taxonomyStore)
```

Keep `@Environment(\.modelContext)` — `findRecipesButton` still uses it.

- [ ] **Step 3: Fix the `ContentView` preview**

In the `#Preview` in `ContentView.swift`, after `.environment(FavouritesViewModel(modelContext: container.mainContext))` add:

```swift
            .environment(CabinetViewModel(modelContext: container.mainContext))
```

- [ ] **Step 4: Build**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Smoke test on the simulator**

Use `mcp__Claude_Code_iOS_Simulator__control` (`attach`, then `launch` the built `.app` from DerivedData). Cabinet tab: add London Dry Gin → it appears; swipe-delete it → it disappears; switch to Recipes and back → list unchanged. Screenshot for the record.

- [ ] **Step 6: Commit**

```bash
git add ios/NorseMixology
git commit -m "iOS: share one CabinetViewModel app-wide

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `RecipeBrowserViewModel` — browse state and catalog entries

**Files:**
- Modify: `ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift`

**Interfaces:**
- Consumes: `CatalogAvailability.evaluate(recipes:cabinet:index:)`, `GroupedAvailability`, `RecipeBrowseState`, `RecipeFilterOptions`, `GroupedMatchResults.filtered(by:index:)`, `TaxonomyStore.index`.
- Produces (used by Tasks 6–7):
  - `var browseState: RecipeBrowseState`
  - `private(set) var entries: [CatalogEntry]`, `private(set) var filterOptions: RecipeFilterOptions`, `private(set) var familyNamesById: [UUID: String]`
  - `var visibleGrouped: GroupedMatchResults`, `var visibleAvailability: GroupedAvailability`
  - `func entry(for id: UUID) -> CatalogEntry?`, `var selectedEntry: CatalogEntry?`
  - `func clearSelectionIfHidden()`
  - existing `refresh(context:taxonomyStore:)`, `refresh(cabinet:taxonomyStore:)`, `grouped`, `cabinetStyleIds`, `selectedRecipeID`, reveal API unchanged.

- [ ] **Step 1: Add the new state**

Below `var selectedRecipeID: UUID?` add:

```swift
    /// Can make | All recipes, plus the search text and filters (shared by both modes).
    var browseState = RecipeBrowseState()
    /// Every catalog recipe evaluated against the cabinet at the last refresh.
    private(set) var entries: [CatalogEntry] = []
    private(set) var availability = GroupedAvailability.empty
    private(set) var filterOptions = RecipeFilterOptions.empty
    /// For filter chip labels (base spirit family names).
    private(set) var familyNamesById: [UUID: String] = [:]
    /// Replaced on every refresh together with `entries`, which is observed.
    @ObservationIgnored private var index = TaxonomyIndex(categories: [])

    /// The Can make groups with the current search/filters applied.
    var visibleGrouped: GroupedMatchResults { grouped.filtered(by: browseState.filter, index: index) }
    /// The All recipes groups with the current search/filters applied.
    var visibleAvailability: GroupedAvailability { availability.filtered(by: browseState.filter, index: index) }

    func entry(for id: UUID) -> CatalogEntry? {
        entries.first { $0.id == id }
    }

    var selectedEntry: CatalogEntry? {
        selectedRecipeID.flatMap(entry(for:))
    }

    /// Clears the iPad selection when it's no longer in the list on screen
    /// (cabinet change, mode switch, or a filter that hides it).
    func clearSelectionIfHidden() {
        guard let selectedRecipeID else { return }
        let visibleIds: [UUID]
        switch browseState.mode {
        case .canMake: visibleIds = (visibleGrouped.perfect + visibleGrouped.almost + visibleGrouped.exploring).map(\.id)
        case .all: visibleIds = visibleAvailability.allIds
        }
        if !visibleIds.contains(selectedRecipeID) {
            self.selectedRecipeID = nil
        }
    }
```

Delete the old `selectedRecipe` computed property (Task 6 switches its only caller to `selectedEntry`).

- [ ] **Step 2: Compute entries in `refresh(cabinet:taxonomyStore:)`**

Replace the tail of `refresh(cabinet:taxonomyStore:)` — from `results = newResults` to the end of the function — with:

```swift
        results = newResults
        let profile = TasteProfileStore.load()
        grouped = TasteRanking.reorder(GroupedMatchResults(results: results), toward: profile)
        cabinetStyleIds = Set(cabinet.map(\.ingredientStyleId))

        let index = taxonomyStore.index
        self.index = index
        familyNamesById = taxonomyStore.familyNamesById
        entries = CatalogAvailability.evaluate(recipes: taxonomyStore.recipes, cabinet: cabinet, index: index)
        availability = GroupedAvailability(entries: entries, profile: profile)
        filterOptions = RecipeFilterOptions(recipes: taxonomyStore.recipes, index: index)

        // A recipe can drop out of the visible list when the cabinet changes.
        clearSelectionIfHidden()
```

- [ ] **Step 3: Build**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E 'error:|BUILD'`
Expected: one error in `RecipeBrowserView.swift` — `value of type 'RecipeBrowserViewModel' has no member 'selectedRecipe'`. That caller is replaced in Task 6; to keep this task's commit building, change that line now to:

```swift
            if let result = viewModel.selectedEntry?.match {
```

Re-run the build. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios/NorseMixology
git commit -m "iOS: Recipes view model evaluates the whole catalog and holds browse state

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Recipes tab — toggle, search, filters, All recipes list

**Files:**
- Create: `ios/NorseMixology/Recipes/FlowLayout.swift`
- Create: `ios/NorseMixology/Recipes/BrowseHeader.swift`
- Create: `ios/NorseMixology/Recipes/RecipeFilterSheet.swift`
- Create: `ios/NorseMixology/Recipes/CatalogRowView.swift`
- Create: `ios/NorseMixology/Recipes/CatalogList.swift`
- Create: `ios/NorseMixology/Recipes/NoMatchingRecipesView.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeBrowserView.swift` (whole file)
- Modify: `ios/NorseMixology.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Consumes: everything Task 5 produces; `RecipeResultsList` and its `Interaction` enum (existing); `RecipeDetailView(result:cabinetStyleIds:)` (existing — Task 7 switches to the entry initialiser).
- Produces: `RecipeFilter.Criterion.label(familyNamesById:) -> String` (app extension, in `BrowseHeader.swift`), `CatalogList(grouped:interaction:onRefresh:)`, `NoMatchingRecipesView(onClear:)`.

- [ ] **Step 1: `FlowLayout.swift`** — wraps chips onto new lines instead of truncating

```swift
import SwiftUI

/// Lays children out left to right, wrapping to a new line when the row is
/// full — used for filter chips so large text never truncates them.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
```

- [ ] **Step 2: `BrowseHeader.swift`** — mode picker + active filter chips

```swift
import SwiftUI
import NorseMixologyCore

extension RecipeFilter.Criterion {
    /// Chip / filter-row text. Tags are catalog slugs ("spirit-forward").
    func label(familyNamesById: [UUID: String]) -> String {
        switch self {
        case .tag(let tag): return tag.replacingOccurrences(of: "-", with: " ").capitalized
        case .strength(let strength): return strength.displayName
        case .baseFamily(let id): return familyNamesById[id] ?? String(localized: "Unknown spirit")
        case .glass(let glass): return glass.displayName
        case .method(let method): return method.displayName
        case .difficulty(let difficulty): return difficulty.displayName
        }
    }
}

/// Top of the Recipes tab: Can make | All recipes, then one removable chip per active filter.
struct BrowseHeader: View {
    @Environment(RecipeBrowserViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: 10) {
            Picker("Show", selection: $viewModel.browseState.mode) {
                Text("Can make").tag(RecipeBrowseState.Mode.canMake)
                Text("All recipes").tag(RecipeBrowseState.Mode.all)
            }
            .pickerStyle(.segmented)

            if !viewModel.browseState.filter.criteria.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.browseState.filter.criteria, id: \.self) { criterion in
                        chip(criterion)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DesignTokens.background)
    }

    private func chip(_ criterion: RecipeFilter.Criterion) -> some View {
        let label = criterion.label(familyNamesById: viewModel.familyNamesById)
        return Button {
            viewModel.browseState.filter.remove(criterion)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .dsText(.body)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Capsule().fill(DesignTokens.surfaceRaised))
            .overlay(Capsule().strokeBorder(DesignTokens.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove filter \(label)"))
    }
}
```

- [ ] **Step 3: `RecipeFilterSheet.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// Every filter, grouped by kind. Changes apply immediately; "Clear" resets
/// filters (not the search text).
struct RecipeFilterSheet: View {
    @Environment(RecipeBrowserViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let options = viewModel.filterOptions
        NavigationStack {
            Form {
                section("Strength", RecipeFilter.Strength.allCases.map { RecipeFilter.Criterion.strength($0) })
                section("Base spirit", options.baseFamilies.map { RecipeFilter.Criterion.baseFamily($0.id) })
                section("Style", options.tags.map { RecipeFilter.Criterion.tag($0) })
                section("Glass", options.glassTypes.map { RecipeFilter.Criterion.glass($0) })
                section("Method", options.methods.map { RecipeFilter.Criterion.method($0) })
                section("Difficulty", options.difficulties.map { RecipeFilter.Criterion.difficulty($0) })
            }
            .dsListBackground()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        for criterion in viewModel.browseState.filter.criteria {
                            viewModel.browseState.filter.remove(criterion)
                        }
                    }
                    .disabled(viewModel.browseState.filter.criteria.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ criteria: [RecipeFilter.Criterion]) -> some View {
        if !criteria.isEmpty {
            Section {
                ForEach(criteria, id: \.self) { row($0) }
            } header: {
                Text(title)
                    .dsText(.label)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .listRowBackground(DesignTokens.surface)
        }
    }

    private func row(_ criterion: RecipeFilter.Criterion) -> some View {
        let isOn = viewModel.browseState.filter.contains(criterion)
        return Button {
            viewModel.browseState.filter.toggle(criterion)
        } label: {
            HStack {
                Text(criterion.label(familyNamesById: viewModel.familyNamesById))
                    .dsText(.heading)
                    .fontWeight(.regular)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DesignTokens.accent)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
```

- [ ] **Step 4: `CatalogRowView.swift`** — compact row

```swift
import SwiftUI
import NorseMixologyCore

/// One recipe in All recipes: name, glass, and what it still needs.
struct CatalogRowView: View {
    let entry: CatalogEntry
    var isSelected = false

    @Environment(FavouritesViewModel.self) private var favourites

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.recipe.glassType.symbolName)
                .foregroundStyle(DesignTokens.textSecondary)
                .accessibilityLabel(Text("\(entry.recipe.glassType.displayName) glass"))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.recipe.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                statusText
                    .dsText(.body)
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 8)
            if favourites.isFavourited(entry.recipe.id) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(DesignTokens.accent)
                    .accessibilityLabel("Favourite")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? DesignTokens.surfaceRaised : DesignTokens.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? DesignTokens.accent : DesignTokens.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusText: Text {
        if let match = entry.match {
            switch MatchBadgeState(result: match) {
            case .exact: return Text("Ready")
            case .substituted(let count): return count == 1 ? Text("Ready · 1 sub") : Text("Ready · \(count) subs")
            }
        }
        switch entry.missing.count {
        case 0: return Text("Unavailable")
        case 1: return Text("Needs \(entry.missing[0].name)")
        default: return Text("Missing \(entry.missing.count)")
        }
    }

    private var statusColor: Color {
        guard let match = entry.match else { return DesignTokens.textSecondary }
        return match.matchType == .exact ? DesignTokens.matchExact : DesignTokens.matchSubstituted
    }
}
```

- [ ] **Step 5: `CatalogList.swift`**

```swift
import SwiftUI
import NorseMixologyCore

/// All recipes: Ready / Missing 1 / Missing 2 / Missing 3+. Deliberately no
/// entrance or hero animation — this list is for scanning 150+ recipes.
struct CatalogList: View {
    let grouped: GroupedAvailability
    let interaction: RecipeResultsList.Interaction
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                section("Ready", subtitle: "You can make these now", tier: .ready)
                section("Missing 1", subtitle: "One bottle away", tier: .missing1)
                section("Missing 2", subtitle: "Two bottles away", tier: .missing2)
                section("Missing 3+", subtitle: "Worth a shopping trip", tier: .missing3Plus)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .dsScreenBackground()
        .refreshable { onRefresh() }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, tier: AvailabilityTier) -> some View {
        let entries = grouped.entries(in: tier)
        if !entries.isEmpty {
            Section {
                ForEach(entries) { row(for: $0) }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(title) + Text(verbatim: " (\(entries.count))"))
                        .dsText(.heading)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func row(for entry: CatalogEntry) -> some View {
        switch interaction {
        case .push:
            NavigationLink(value: entry.id) { CatalogRowView(entry: entry) }
                .buttonStyle(.plain)
        case .select(let selectedID, let onSelect):
            Button { onSelect(entry.id) } label: {
                CatalogRowView(entry: entry, isSelected: entry.id == selectedID)
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 6: `NoMatchingRecipesView.swift`**

```swift
import SwiftUI

/// Search/filters hide every recipe.
struct NoMatchingRecipesView: View {
    let onClear: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No recipes match", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try a different search or remove a filter.")
        } actions: {
            Button("Clear filters", action: onClear)
                .buttonStyle(.dsPrimary)
                .frame(maxWidth: 280)
        }
        .dsScreenBackground()
    }
}
```

- [ ] **Step 7: Rewrite `RecipeBrowserView.swift`**

```swift
import SwiftUI
import SwiftData
import NorseMixologyCore

/// The Recipes tab: Can make (matches for the current cabinet, grouped into
/// Perfect Match / Almost There / Worth Exploring) or All recipes (the whole
/// catalog grouped by how much is missing). Search and filters apply to both.
///
/// Compact width pushes the detail screen with `NavigationStack`; regular
/// width (iPad) shows list and detail side by side in a `NavigationSplitView`.
struct RecipeBrowserView: View {
    @Environment(RecipeBrowserViewModel.self) private var viewModel
    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Remembered across launches; search text and filters deliberately are not.
    @SceneStorage("recipes.browseMode") private var storedMode = RecipeBrowseState.Mode.canMake.rawValue
    @State private var isPresentingFilters = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .onAppear {
            if let mode = RecipeBrowseState.Mode(rawValue: storedMode) {
                viewModel.browseState.mode = mode
            }
            refresh()
        }
        // The bundled catalog loads asynchronously at launch; re-match once it lands.
        .onChange(of: taxonomyStore.recipesLoaded) { refresh() }
        .onChange(of: viewModel.browseState) {
            storedMode = viewModel.browseState.mode.rawValue
            viewModel.clearSelectionIfHidden()
        }
        .sheet(isPresented: $isPresentingFilters) {
            RecipeFilterSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func refresh() {
        viewModel.refresh(context: modelContext, taxonomyStore: taxonomyStore)
    }

    private var stackLayout: some View {
        NavigationStack {
            browser(interaction: .push)
                .navigationDestination(for: UUID.self) { id in
                    detail(for: id)
                }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            browser(interaction: .select(selectedID: viewModel.selectedRecipeID) { viewModel.selectedRecipeID = $0 })
        } detail: {
            if let id = viewModel.selectedRecipeID {
                detail(for: id)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "Select a Recipe",
                    systemImage: "wineglass",
                    description: Text("Pick a cocktail from the list to see how to make it.")
                )
            }
        }
    }

    @ViewBuilder
    private func detail(for id: UUID) -> some View {
        if let result = viewModel.entry(for: id)?.match {
            RecipeDetailView(result: result, cabinetStyleIds: viewModel.cabinetStyleIds)
        } else if let entry = viewModel.entry(for: id) {
            RecipeDetailView(recipe: entry.recipe, match: nil, cabinetStyleIds: viewModel.cabinetStyleIds)
        } else {
            ContentUnavailableView("This recipe is no longer available", systemImage: "wineglass")
        }
    }

    private func browser(interaction: RecipeResultsList.Interaction) -> some View {
        @Bindable var viewModel = viewModel
        return list(interaction: interaction)
            .safeAreaInset(edge: .top, spacing: 0) { BrowseHeader() }
            .searchable(text: $viewModel.browseState.filter.query, prompt: Text("Recipes or ingredients"))
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let active = !viewModel.browseState.filter.criteria.isEmpty
                    Button {
                        isPresentingFilters = true
                    } label: {
                        Label("Filters", systemImage: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityValue(active ? Text("\(viewModel.browseState.filter.criteria.count) active") : Text("None active"))
                }
            }
    }

    @ViewBuilder
    private func list(interaction: RecipeResultsList.Interaction) -> some View {
        switch viewModel.browseState.mode {
        case .canMake:
            // An empty cabinet keeps RecipeResultsList's own empty message.
            if !viewModel.grouped.isEmpty && viewModel.visibleGrouped.isEmpty {
                NoMatchingRecipesView(onClear: clearFilters)
            } else {
                RecipeResultsList(grouped: viewModel.visibleGrouped, interaction: interaction, onRefresh: refresh)
            }
        case .all:
            if viewModel.visibleAvailability.isEmpty, !viewModel.browseState.filter.isEmpty {
                NoMatchingRecipesView(onClear: clearFilters)
            } else {
                CatalogList(grouped: viewModel.visibleAvailability, interaction: interaction, onRefresh: refresh)
            }
        }
    }

    private func clearFilters() {
        viewModel.browseState.filter.clear()
    }
}
```

- [ ] **Step 8: Register the new files and build**

Run:
```bash
cd ios && xcodegen generate && git diff --stat NorseMixology.xcodeproj
```
Expected: `project.pbxproj` changed (new file entries; ID churn on `FloatingIcon.swift` is expected and harmless).

Run:
```bash
cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tee "${TMPDIR:-/tmp}/nm-build.log" | tail -1
grep -oE 'SwiftCompile normal [^ ]+ [^ ]*(FlowLayout|BrowseHeader|RecipeFilterSheet|CatalogRowView|CatalogList|NoMatchingRecipesView)\.swift' "${TMPDIR:-/tmp}/nm-build.log" | sort -u | wc -l
```
Expected: `** BUILD SUCCEEDED **` and `6` (every new file compiled). If the count is lower, the file is missing from the target — re-run `xcodegen generate`.

- [ ] **Step 9: Simulator check**

Launch on iPhone 17 Pro (`mcp__Claude_Code_iOS_Simulator__control`). With a cabinet of London Dry Gin + Lime Juice + Raspberry Liqueur:
1. Recipes tab shows the Can make | All recipes picker; Can make looks exactly as before.
2. All recipes → sections Ready / Missing 1 / … ; Last Word row reads "Needs Green Chartreuse".
3. Search "chartreuse" → only Chartreuse recipes; switch to Can make → search stays applied.
4. Filters → Method: Stir → chip "Stir" appears; tap its ✕ → chip gone.
5. Search "zzzz" → "No recipes match" → Clear filters restores the list.
6. Kill and relaunch → mode is still All recipes; search and filters are empty.
Screenshot steps 2 and 5.

- [ ] **Step 10: Commit**

```bash
git add ios/NorseMixology ios/NorseMixology.xcodeproj
git commit -m "iOS: Recipes tab — Can make | All recipes, search, filters, catalog list

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Recipe screen — show substitutions on unmakeable recipes and add missing ingredients

**Files:**
- Modify: `ios/NorseMixology/Recipes/IngredientRowView.swift` (properties + `body`)
- Modify: `ios/NorseMixology/Recipes/RecipeDetailView.swift` (properties, inits, `ingredientsSection`, sheet)
- Modify: `ios/NorseMixology/Recipes/RecipeBrowserView.swift` (`detail(for:)`)

**Interfaces:**
- Consumes: `CatalogEntry` (Task 1), `CabinetViewModel` from the environment (Task 4), `RecipeBrowserViewModel.refresh(cabinet:taxonomyStore:)` and `entry(for:)` (Task 5), existing `AddIngredientConfirmationView(style:cabinetViewModel:taxonomyStore:onAdded:)`.
- Produces: `RecipeDetailView(entry: CatalogEntry, cabinetStyleIds: Set<UUID>)`; `IngredientRowView(..., onAdd: (() -> Void)?)`.

- [ ] **Step 1: Add the button to `IngredientRowView`**

Add under `let substitute: SubstitutionDetail?`:

```swift
    /// Set only for a missing *required* ingredient: shows a trailing "add to cabinet" button.
    var onAdd: (() -> Void)? = nil
```

Replace the `else { rowContent(substitute: nil) }` branch at the end of `body` with:

```swift
        } else if let onAdd {
            HStack(alignment: .top, spacing: 4) {
                rowContent(substitute: nil)
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
        } else {
            rowContent(substitute: nil)
        }
```

(The button sits outside `rowContent`, whose `.accessibilityElement(children: .combine)` would otherwise swallow it.)

- [ ] **Step 2: Entry initialiser and stored substitutions in `RecipeDetailView`**

Replace the stored properties and both initialisers (lines 11–31: `let recipe` … `private var substitutions`) with:

```swift
    let recipe: Recipe
    let match: RecipeMatchResult?
    let cabinetStyleIds: Set<UUID>
    /// Substituted ingredients — from the match, or (for a recipe that isn't
    /// makeable yet) from its `CatalogEntry`.
    private let substitutions: [SubstitutionDetail]
    /// Required ingredients nothing in the cabinet covers; these rows get an add button.
    private let missingStyleIds: Set<UUID>

    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(FavouritesViewModel.self) private var favourites
    @Environment(CabinetViewModel.self) private var cabinet
    @Environment(RecipeBrowserViewModel.self) private var browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heartIsPulsing = false
    @State private var addingStyle: IngredientStyle?
    @State private var addedCount = 0
    @ScaledMetric(relativeTo: .caption) private var stepBadgeSize: CGFloat = 22

    /// Favourites: no add buttons (out of scope for this release).
    init(recipe: Recipe, match: RecipeMatchResult?, cabinetStyleIds: Set<UUID>) {
        self.recipe = recipe
        self.match = match
        self.cabinetStyleIds = cabinetStyleIds
        self.substitutions = match?.substitutions ?? []
        self.missingStyleIds = []
    }

    init(result: RecipeMatchResult, cabinetStyleIds: Set<UUID>) {
        self.init(recipe: result.recipe, match: result, cabinetStyleIds: cabinetStyleIds)
    }

    /// Recipes tab (both modes).
    init(entry: CatalogEntry, cabinetStyleIds: Set<UUID>) {
        self.recipe = entry.recipe
        self.match = entry.match
        self.cabinetStyleIds = cabinetStyleIds
        self.substitutions = entry.substitutions
        self.missingStyleIds = Set(entry.missing.map(\.id))
    }
```

Update the type's doc comment last paragraph to: ``/// `match` is `nil` for a recipe the current cabinet can't make. From the Recipes tab its missing required ingredients get an "add to cabinet" button; from Favourites they don't.``

Note: the substitution callout already keys off `!substitutions.isEmpty`, so an unmakeable recipe with a working substitute now shows the callout too — intended.

- [ ] **Step 3: Wire the add button in `ingredientsSection`**

Replace the `ForEach(...) { row in IngredientRowView(...) }` with:

```swift
                ForEach(RecipeAvailability.rows(for: recipe, substitutions: substitutions, cabinetStyleIds: cabinetStyleIds)) { row in
                    let style = taxonomyStore.stylesById[row.ingredient.ingredientStyleId]
                    let canAdd = row.status == .unavailable && style.map { missingStyleIds.contains($0.id) } == true
                    IngredientRowView(
                        name: style?.name ?? "Unknown ingredient",
                        ingredient: row.ingredient,
                        status: row.status,
                        substitute: row.substitution,
                        onAdd: canAdd ? { addingStyle = style } : nil
                    )
                }
```

- [ ] **Step 4: The add sheet, haptic and announcement**

Add after the `.toolbar { ... }` modifier in `body`:

```swift
        .sheet(item: $addingStyle) { style in
            AddIngredientConfirmationView(style: style, cabinetViewModel: cabinet, taxonomyStore: taxonomyStore) {
                addingStyle = nil
                browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)
                addedCount += 1
                AccessibilityNotification.Announcement(String(localized: "Added to cabinet")).post()
            }
        }
        .sensoryFeedback(.success, trigger: addedCount)
```

- [ ] **Step 5: Use the entry initialiser in the browser**

In `RecipeBrowserView.swift`, replace the body of `detail(for:)` with:

```swift
        if let entry = viewModel.entry(for: id) {
            RecipeDetailView(entry: entry, cabinetStyleIds: viewModel.cabinetStyleIds)
        } else {
            ContentUnavailableView("This recipe is no longer available", systemImage: "wineglass")
        }
```

Because `detail(for:)` re-reads the entry from the observed view model, the open screen updates in place after an add (row turns exact, header badge changes).

- [ ] **Step 6: Build**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -1`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Simulator check (spec §5 end-to-end)**

Cabinet: London Dry Gin, Lime Juice, Raspberry Liqueur. Then:
1. Recipes → All recipes → search "chartreuse" → open **Last Word**: Green Chartreuse row is unavailable with a ⊕ button; header pill "Missing ingredients".
2. Open **Negroni** (missing vermouth + Bitter Aperitif): both have ⊕; the orange-wheel garnish row is unavailable with **no** ⊕.
3. Back in Last Word, tap ⊕ → confirmation sheet → Add to Cabinet → sheet closes, success haptic, row turns exact, header shows "✓ All ingredients".
4. Back → Last Word now in **Ready**; switch to Can make → Last Word listed.
5. Cabinet: Rye Whiskey + Angostura only → All recipes → **Old Fashioned** → Bourbon row shows "Using Rye Whiskey" (substituted) and the Substitutions callout; Demerara Syrup has ⊕.
6. Favourites: open a favourite the cabinet can't make → no ⊕ buttons (unchanged behaviour).
7. VoiceOver labels: inspect the ⊕ button's accessibility label reads "Add Green Chartreuse to cabinet".
8. Repeat 1–4 on **iPad Pro 11-inch (M5)**: split view; after the add, the detail pane updates and the selection stays.
Screenshot steps 1, 3 and 5.

- [ ] **Step 8: Commit**

```bash
git add ios/NorseMixology
git commit -m "iOS: add missing ingredients to the cabinet from the recipe screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Strings, docs, final verification

**Files:**
- Modify: `ios/NorseMixology/Localizable.xcstrings` (via script)
- Modify: `NORSE_MIXOLOGY_BUILD.md` (new section after "iOS taste profile & onboarding (Phase 11)")
- Modify: `docs/superpowers/specs/2026-10-04-recipe-catalog-browse-design.md` (amendments)

- [ ] **Step 1: Sync the String Catalog**

Run: `cd ios && scripts/sync-strings.sh`
Expected: `Synced NorseMixology/Localizable.xcstrings`. Then `git diff --stat ios/NorseMixology/Localizable.xcstrings` shows additions; spot-check that "All recipes", "No recipes match", "Add %@ to cabinet" and "Needs %@" are present:

```bash
grep -c -E '"(All recipes|No recipes match|Add %@ to cabinet|Needs %@)"' ios/NorseMixology/Localizable.xcstrings
```
Expected: `4`.

- [ ] **Step 2: Add the build-reference section**

Insert into `NORSE_MIXOLOGY_BUILD.md`, directly before `## Design System — "Modern Neon Bar"`:

```markdown
## Recipe catalog browse (iOS)

- **Spec:** `docs/superpowers/specs/2026-10-04-recipe-catalog-browse-design.md`. Roadmap sub-project A.
- **Additive only.** `CatalogAvailability.evaluate` takes "Ready" from `MatchingService.match` itself and, for every other recipe, reuses the engine's per-ingredient `resolve` (now `internal`, not `private` — the only engine change) to list `missing` (required, unresolvable, recipe order, de-duplicated) and the substitutions that already work. Invariant, unit-tested: Ready in All recipes ⇔ listed in Can make.
- **Tiers:** Ready / Missing 1 / Missing 2 / Missing 3+ (`GroupedAvailability`). Ready ordered like the engine; Missing tiers by count then name; an active taste profile re-sorts within each tier (`TasteRanking.sorted`, same no-op rule as `reorder`).
- **Search & filters (`RecipeFilter`)** apply to both modes. Query: trimmed, case- and diacritic-insensitive, matches recipe name then ingredient style/family names. Criteria: strength (`no-abv`/`low-abv` tags), base spirit (family of the `.base`-role ingredient), curated style tags, glass, method, difficulty; AND across kinds, OR within one. Can make is filtered without re-running the engine.
- **Persistence:** mode in `@SceneStorage("recipes.browseMode")`; query and filters only for the session.
- **Add to cabinet:** only rows in `entry.missing` get the ⊕ button (never optional/garnish rows). One `CabinetViewModel` is injected at the app root and shared by Cabinet and the recipe screen. Favourites' detail has no add buttons.
- **Android parity:** not ported (Android paused). A port needs the same "Ready ⇔ engine result" rule.
```

- [ ] **Step 3: Amend the spec to match what was built**

In the spec:
- §2 `RecipeFilter` block: replace the `tags/strengths/baseFamilyIds/glassTypes/methods/difficulties` properties with `query` + `criteria: [Criterion]` (`tag`, `strength`, `baseFamily`, `glass(GlassType)`, `method(Method)`, `difficulty(Difficulty)`) and `toggle/remove/contains/clear`; note glass/method/difficulty use the existing enums, not strings.
- §5 Simulator verification: replace "search "violette" → open Aviation → Add Crème de violette" with "cabinet London Dry Gin + Lime Juice + Raspberry Liqueur → search "chartreuse" → open Last Word → Add Green Chartreuse" (the bundled Aviation uses raspberry liqueur).
- Set **Status:** to `Implemented 2026-10-05`.

- [ ] **Step 4: Final verification**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: `Executed 187 tests, with 0 failures`.

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -1`
Expected: `** BUILD SUCCEEDED **`

Simulator, Reduce Motion on (Settings → Accessibility → Motion) and largest Dynamic Type: All recipes and the filter sheet render without truncated chips; adding an ingredient does not animate tier moves.

- [ ] **Step 5: Commit**

```bash
git add ios/NorseMixology/Localizable.xcstrings NORSE_MIXOLOGY_BUILD.md docs/superpowers/specs/2026-10-04-recipe-catalog-browse-design.md
git commit -m "docs: recipe catalog browse build notes; sync string catalog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
