# iOS Taste Profile & Animated Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 5-question animated "this-or-that" taste quiz to iOS that builds a `UserTasteProfile`, persists it locally, and uses it to break ties within the Recipe Browser's existing match tiers — without ever touching the core matching algorithm.

**Architecture:** Two new pure, testable types in `NorseMixologyCore` (`UserTasteProfile` model + `TasteProfileStore` persistence), one new pure ranking type (`TasteRanking`) that re-sorts an already-computed `GroupedMatchResults` by cosine similarity over 5 axes, and a new SwiftUI onboarding flow + Settings tab in the app target. `RecipeBrowserViewModel.refresh` gains one extra line calling `TasteRanking.reorder`. Everything is additive — no existing public signature in `MatchingService`, `RecipePresentation.swift`, or `Recipe`/`FlavorProfile` changes.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, `@Observable`, XCTest (SPM `swift test` for `NorseMixologyCore`), native SwiftUI `.spring`/`.easeIn` animations (no Lottie).

**Spec:** `Phases/Phase 11 - iOS Taste Profile & Animated Onboarding.md` in the Obsidian vault (`/Users/mlj/Library/Mobile Documents/iCloud~md~obsidian/Documents/Project Ideas/Dev Project Ideas/Norse Mixology/Phases/Phase 11 - iOS Taste Profile & Animated Onboarding.md`)

## Global Constraints

- **Never modify** `MatchingService`, `MatchPreferences`, `RecipeMatchResult`, `MatchType`, or `GroupedMatchResults`'s bucketing logic — the cross-platform matching spec (`Data Model.md`) stays exactly as documented even though Android is paused.
- `TasteRanking.similarity` must **not** reuse `FlavorSimilarity.cosine` (9-dimension) — implement a separate 5-axis (sweetness, bitterness, citrus, smokiness, herbal) cosine so un-quizzed axes (floral, spice, fruity, oaky) never bias ranking.
- `UserTasteProfile` has exactly 6 fields: `sweetness`, `bitterness`, `citrus`, `smokiness`, `herbal` (`Double`, default `0.5`), `hasCompletedOnboarding` (`Bool`, default `false`). No `floral`/`spice`/`fruity`/`oaky` fields, ever.
- `TasteProfileStore.load`/`.save` take an injected `UserDefaults` parameter (default `.standard`) — never hardcode `.standard` inside the implementation, so tests can pass `UserDefaults(suiteName:)`.
- Native SwiftUI animation only. No Lottie package, no custom particle system.
- Every interactive element (quiz card halves, Skip, Cancel, Retake Quiz) must be a real `Button`, independently focusable by VoiceOver — never gesture-only (Phase 6 hardening rule).
- This phase is iOS-only. Do not touch anything under `android/`.
- Existing-install migration: if a profile is uncompleted but the device already has any `CabinetItem` or `FavouriteRecipe`, silently persist a neutral *completed* profile instead of showing the quiz.

---

## File Structure

**New files:**
- `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/UserTasteProfile.swift` — the model
- `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/TasteProfileStore.swift` — persistence
- `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/TasteRanking.swift` — similarity + reorder
- `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/UserTasteProfileTests.swift`
- `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/TasteRankingTests.swift`
- `ios/NorseMixology/Onboarding/TasteQuizQuestion.swift` — static quiz data
- `ios/NorseMixology/Onboarding/ThisOrThatCard.swift` — draggable/tappable card
- `ios/NorseMixology/Onboarding/TasteOnboardingView.swift` — the quiz flow + celebration
- `ios/NorseMixology/Settings/SettingsView.swift` — taste display + retake

**Modified files:**
- `ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift` — call `TasteRanking.reorder` in `refresh(cabinet:taxonomyStore:)`
- `ios/NorseMixology/ContentView.swift` — show `TasteOnboardingView` instead of the `TabView` pre-completion; add the Settings tab
- `ios/NorseMixology/NorseMixologyApp.swift` — resolve the initial onboarding/migration decision synchronously in `init()`

---

## Task 1: `UserTasteProfile` model

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/UserTasteProfile.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/UserTasteProfileTests.swift`

**Interfaces:**
- Produces: `public struct UserTasteProfile: Codable, Equatable, Sendable` with `var sweetness, bitterness, citrus, smokiness, herbal: Double` (each defaulting to `0.5`), `var hasCompletedOnboarding: Bool` (defaulting to `false`), a memberwise `public init(sweetness:bitterness:citrus:smokiness:herbal:hasCompletedOnboarding:)` with all defaults, and `public static let neutral = UserTasteProfile()`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import NorseMixologyCore

final class UserTasteProfileTests: XCTestCase {
    func testDefaultsAreAllNeutral() {
        let profile = UserTasteProfile()
        XCTAssertEqual(profile.sweetness, 0.5)
        XCTAssertEqual(profile.bitterness, 0.5)
        XCTAssertEqual(profile.citrus, 0.5)
        XCTAssertEqual(profile.smokiness, 0.5)
        XCTAssertEqual(profile.herbal, 0.5)
        XCTAssertFalse(profile.hasCompletedOnboarding)
        XCTAssertEqual(profile, UserTasteProfile.neutral)
    }

    func testRoundTripsThroughCodable() throws {
        let profile = UserTasteProfile(
            sweetness: 0.85, bitterness: 0.15, citrus: 0.5,
            smokiness: 0.85, herbal: 0.15, hasCompletedOnboarding: true
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserTasteProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter UserTasteProfileTests`
Expected: FAIL to compile — `UserTasteProfile` does not exist.

- [ ] **Step 3: Implement the model**

```swift
import Foundation

/// The user's flavour leanings on the 5 axes quizzed during onboarding
/// (see `Phases/Phase 11 - iOS Taste Profile & Animated Onboarding.md`).
/// Used only to break ties within an already-computed `GroupedMatchResults`
/// tier — never fed into `MatchingService`/`matchScore`.
///
/// Deliberately has no `floral`/`spice`/`fruity`/`oaky` fields: those axes
/// are never quizzed, so defaulting and comparing them would silently bias
/// ranking toward recipes that happen to sit near 0.5 on axes the user was
/// never asked about.
public struct UserTasteProfile: Codable, Equatable, Sendable {
    public var sweetness: Double
    public var bitterness: Double
    public var citrus: Double
    public var smokiness: Double
    public var herbal: Double
    public var hasCompletedOnboarding: Bool

    public init(
        sweetness: Double = 0.5,
        bitterness: Double = 0.5,
        citrus: Double = 0.5,
        smokiness: Double = 0.5,
        herbal: Double = 0.5,
        hasCompletedOnboarding: Bool = false
    ) {
        self.sweetness = sweetness
        self.bitterness = bitterness
        self.citrus = citrus
        self.smokiness = smokiness
        self.herbal = herbal
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// All axes at the midpoint, onboarding not completed — the value `load()`
    /// returns when nothing has been saved yet.
    public static let neutral = UserTasteProfile()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter UserTasteProfileTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/UserTasteProfile.swift ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/UserTasteProfileTests.swift
git commit -m "iOS: add UserTasteProfile model (Phase 11)"
```

---

## Task 2: `TasteProfileStore`

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/TasteProfileStore.swift`
- Modify (append to): `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/UserTasteProfileTests.swift`

**Interfaces:**
- Consumes: `UserTasteProfile` (Task 1), `UserTasteProfile.neutral`
- Produces: `public enum TasteProfileStore` with `public static func load(defaults: UserDefaults = .standard) -> UserTasteProfile` and `public static func save(_ profile: UserTasteProfile, defaults: UserDefaults = .standard)`

- [ ] **Step 1: Write the failing tests**

Append to `UserTasteProfileTests.swift`:

```swift
final class TasteProfileStoreTests: XCTestCase {
    private let suiteName = "TasteProfileStoreTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLoadReturnsNeutralWhenNothingSaved() {
        XCTAssertEqual(TasteProfileStore.load(defaults: defaults), .neutral)
    }

    func testSaveThenLoadRoundTrips() {
        let profile = UserTasteProfile(
            sweetness: 0.85, bitterness: 0.15, citrus: 0.5,
            smokiness: 0.85, herbal: 0.15, hasCompletedOnboarding: true
        )
        TasteProfileStore.save(profile, defaults: defaults)
        XCTAssertEqual(TasteProfileStore.load(defaults: defaults), profile)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter TasteProfileStoreTests`
Expected: FAIL to compile — `TasteProfileStore` does not exist.

- [ ] **Step 3: Implement the store**

```swift
import Foundation

/// Persists the user's `UserTasteProfile` as a single JSON blob in
/// `UserDefaults`. `defaults` is an injected parameter (not hardcoded to
/// `.standard`) so tests can use `UserDefaults(suiteName:)` — the same
/// testability pattern as the app's other services.
public enum TasteProfileStore {
    private static let key = "com.norsemixology.userTasteProfile"

    public static func load(defaults: UserDefaults = .standard) -> UserTasteProfile {
        guard
            let data = defaults.data(forKey: key),
            let profile = try? JSONDecoder().decode(UserTasteProfile.self, from: data)
        else {
            return .neutral
        }
        return profile
    }

    public static func save(_ profile: UserTasteProfile, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter "UserTasteProfileTests|TasteProfileStoreTests"`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/TasteProfileStore.swift ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/UserTasteProfileTests.swift
git commit -m "iOS: add TasteProfileStore persistence (Phase 11)"
```

---

## Task 3: `TasteRanking`

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/TasteRanking.swift`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/TasteRankingTests.swift`

**Interfaces:**
- Consumes: `UserTasteProfile` (Task 1); `FlavorProfile` (existing, `Models/FlavorProfile.swift`); `GroupedMatchResults`, `RecipeMatchResult` (existing, `Models/RecipePresentation.swift` / `Models/MatchingModels.swift`); `Recipe`, `RecipeIngredient`, `GlassType`, `Method`, `Difficulty` (existing, `Models/Recipe.swift`)
- Produces: `public enum TasteRanking` with `public static func similarity(_ profile: UserTasteProfile, to flavor: FlavorProfile) -> Double` and `public static func reorder(_ grouped: GroupedMatchResults, toward profile: UserTasteProfile) -> GroupedMatchResults`

**Design note for the implementer:** `reorder` treats a profile as a no-op in two cases: `hasCompletedOnboarding == false`, or the 5 axes are all still exactly `0.5` (the value saved by the onboarding Skip path in Task 6 — `UserTasteProfile(hasCompletedOnboarding: true)`). Checking axis values directly (rather than `profile == .neutral`) is required because `.neutral` itself has `hasCompletedOnboarding == false`, but the Skip path produces a *different* struct (same axis values, `hasCompletedOnboarding: true`) that must *also* be a no-op — otherwise Skip would still shuffle tied Perfect Matches by an arbitrary direction. `reorder` rebuilds a `GroupedMatchResults` by concatenating the three tiers (each independently sorted) back through `GroupedMatchResults.init(results:)` — this is the only public way to construct one, and it re-derives the exact same buckets from `matchType`/`substitutions.count`, so tier partitioning is untouched. Swift's `sorted(by:)` has been stable since Swift 5, so ties in similarity preserve the engine's original relative order.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import NorseMixologyCore

final class TasteRankingTests: XCTestCase {
    private func flavor(
        sweetness: Double = 0.5, bitterness: Double = 0.5, smokiness: Double = 0.5,
        citrus: Double = 0.5, herbal: Double = 0.5, oaky: Double = 0
    ) -> FlavorProfile {
        FlavorProfile(
            sweetness: sweetness, bitterness: bitterness, smokiness: smokiness,
            citrus: citrus, floral: 0, spice: 0, herbal: herbal, fruity: 0, oaky: oaky, abv: 40
        )
    }

    private func recipe(name: String, flavorProfile: FlavorProfile) -> Recipe {
        Recipe(
            id: UUID(), name: name, description: "", glassType: .rocks, method: .stir,
            ingredients: [], steps: [], flavorProfile: flavorProfile, tags: [],
            difficulty: .easy, imageURL: nil
        )
    }

    private func result(
        name: String, flavorProfile: FlavorProfile,
        matchType: MatchType = .exact, substitutions: [SubstitutionDetail] = []
    ) -> RecipeMatchResult {
        RecipeMatchResult(
            recipe: recipe(name: name, flavorProfile: flavorProfile),
            matchScore: matchType == .exact ? 1.0 : 0.8,
            matchType: matchType,
            substitutions: substitutions
        )
    }

    func testSimilarityIgnoresUnquizzedAxes() {
        let a = flavor(oaky: 0.1)
        let b = flavor(oaky: 0.9)
        let profile = UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: true)
        XCTAssertEqual(TasteRanking.similarity(profile, to: a), TasteRanking.similarity(profile, to: b), accuracy: 0.0001)
    }

    func testReorderSortsSweeterRecipeFirstForSweetLeaningProfile() {
        let dry = result(name: "Dry", flavorProfile: flavor(sweetness: 0.1))
        let sweet = result(name: "Sweet", flavorProfile: flavor(sweetness: 0.9))
        let grouped = GroupedMatchResults(results: [dry, sweet])
        let profile = UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: true)

        let reordered = TasteRanking.reorder(grouped, toward: profile)

        XCTAssertEqual(reordered.perfect.map(\.recipe.name), ["Sweet", "Dry"])
    }

    func testReorderPreservesOrderWhenOnlyAnUnquizzedAxisDiffers() {
        let first = result(name: "First", flavorProfile: flavor(oaky: 0.1))
        let second = result(name: "Second", flavorProfile: flavor(oaky: 0.9))
        let grouped = GroupedMatchResults(results: [first, second])
        let profile = UserTasteProfile(bitterness: 0.9, hasCompletedOnboarding: true)

        let reordered = TasteRanking.reorder(grouped, toward: profile)

        XCTAssertEqual(reordered.perfect.map(\.recipe.name), ["First", "Second"])
    }

    func testReorderIsNoOpForUncompletedProfile() {
        let a = result(name: "A", flavorProfile: flavor(sweetness: 0.1))
        let b = result(name: "B", flavorProfile: flavor(sweetness: 0.9))
        let grouped = GroupedMatchResults(results: [a, b])
        let uncompleted = UserTasteProfile(sweetness: 0.9, hasCompletedOnboarding: false)

        XCTAssertEqual(TasteRanking.reorder(grouped, toward: .neutral), grouped)
        XCTAssertEqual(TasteRanking.reorder(grouped, toward: uncompleted), grouped)
    }

    func testReorderIsNoOpForSkipPathProfile() {
        let a = result(name: "A", flavorProfile: flavor(sweetness: 0.1))
        let b = result(name: "B", flavorProfile: flavor(sweetness: 0.9))
        let grouped = GroupedMatchResults(results: [a, b])
        let skipped = UserTasteProfile(hasCompletedOnboarding: true) // all axes default 0.5

        XCTAssertEqual(TasteRanking.reorder(grouped, toward: skipped), grouped)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter TasteRankingTests`
Expected: FAIL to compile — `TasteRanking` does not exist.

- [ ] **Step 3: Implement `TasteRanking`**

```swift
import Foundation

/// Re-ranks an already-computed `GroupedMatchResults` by how closely each
/// recipe's flavour matches the user's `UserTasteProfile` — a secondary sort
/// within each tier, never a change to `matchScore`/`matchType`/tier
/// membership (see `Data Model.md` "Matching Score & Strictness", which this
/// type must never touch).
public enum TasteRanking {
    /// Cosine similarity over only the 5 quizzed axes. Deliberately does not
    /// reuse `FlavorSimilarity.cosine` — that compares all 9 `FlavorProfile`
    /// dimensions, which would let un-quizzed axes (floral, spice, fruity,
    /// oaky) bias the result.
    public static func similarity(_ profile: UserTasteProfile, to flavor: FlavorProfile) -> Double {
        let pairs: [(Double, Double)] = [
            (profile.sweetness, flavor.sweetness),
            (profile.bitterness, flavor.bitterness),
            (profile.citrus, flavor.citrus),
            (profile.smokiness, flavor.smokiness),
            (profile.herbal, flavor.herbal),
        ]
        let dot = pairs.reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = (pairs.reduce(0.0) { $0 + $1.0 * $1.0 }).squareRoot()
        let magB = (pairs.reduce(0.0) { $0 + $1.1 * $1.1 }).squareRoot()
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    /// A neutral (all axes still 0.5) or uncompleted profile is a no-op —
    /// the original matchScore-descending order is preserved.
    public static func reorder(_ grouped: GroupedMatchResults, toward profile: UserTasteProfile) -> GroupedMatchResults {
        let hasNeutralAxes = profile.sweetness == 0.5 && profile.bitterness == 0.5
            && profile.citrus == 0.5 && profile.smokiness == 0.5 && profile.herbal == 0.5
        guard profile.hasCompletedOnboarding, !hasNeutralAxes else { return grouped }

        func sortedByTaste(_ results: [RecipeMatchResult]) -> [RecipeMatchResult] {
            results.sorted {
                similarity(profile, to: $0.recipe.flavorProfile) > similarity(profile, to: $1.recipe.flavorProfile)
            }
        }

        return GroupedMatchResults(
            results: sortedByTaste(grouped.perfect) + sortedByTaste(grouped.almost) + sortedByTaste(grouped.exploring)
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter TasteRankingTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Run the full Core test suite to confirm no regressions**

Run: `cd ios/Packages/NorseMixologyCore && swift test`
Expected: PASS (all existing + new tests, no failures)

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/TasteRanking.swift ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/TasteRankingTests.swift
git commit -m "iOS: add TasteRanking secondary sort (Phase 11)"
```

---

## Task 4: Wire `TasteRanking` into `RecipeBrowserViewModel`

**Files:**
- Modify: `ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift:34-47`

**Interfaces:**
- Consumes: `TasteRanking.reorder(_:toward:)` (Task 3), `TasteProfileStore.load()` (Task 2)
- Produces: no change to `RecipeBrowserViewModel`'s public surface — `refresh(context:taxonomyStore:)`, `refresh(cabinet:taxonomyStore:)`, `grouped`, `perfectMatches`/`almostMatches`/`explorationMatches` keep their existing signatures, so `RecipeBrowserView.swift` and `RecipeResultsList.swift` need no changes.

This is app-target code with no XCTest target backing it (only `NorseMixologyCore` has a test target in this project — app-level logic is verified by building and, at the end of this plan, manual simulator verification). Keep this change to exactly the two lines below.

- [ ] **Step 1: Modify `refresh(cabinet:taxonomyStore:)`**

In `RecipeBrowserViewModel.swift`, change:

```swift
        grouped = GroupedMatchResults(results: results)
        cabinetStyleIds = Set(cabinet.map(\.ingredientStyleId))
```

to:

```swift
        grouped = GroupedMatchResults(results: results)
        grouped = TasteRanking.reorder(grouped, toward: TasteProfileStore.load())
        cabinetStyleIds = Set(cabinet.map(\.ingredientStyleId))
```

- [ ] **Step 2: Build the app target to confirm it compiles**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift
git commit -m "iOS: apply taste ranking as a secondary sort in RecipeBrowserViewModel (Phase 11)"
```

---

## Task 5: `TasteQuizQuestion` + `ThisOrThatCard`

**Files:**
- Create: `ios/NorseMixology/Onboarding/TasteQuizQuestion.swift`
- Create: `ios/NorseMixology/Onboarding/ThisOrThatCard.swift`

**Interfaces:**
- Consumes: `UserTasteProfile` (Task 1, for the `WritableKeyPath`); `DesignTokens`, `DSTextStyle`, `.dsText(_:)` (existing, `Theme/DesignTokens.swift`)
- Produces:
  - `struct TasteQuizQuestion: Identifiable` with `let id: Int`, `let axis: WritableKeyPath<UserTasteProfile, Double>`, `let leftLabel: String`, `let rightLabel: String`, and `static let all: [TasteQuizQuestion]` (5 entries, fixed order: Sweetness, Bitterness, Citrus, Smokiness, Herbal)
  - `struct ThisOrThatCard: View` with `enum Choice { case left, right }`, `let question: TasteQuizQuestion`, `let onChoose: (Choice) -> Void`

No XCTest coverage — these are SwiftUI view/data types with no branching logic worth a unit test (the 5-question fixed order is directly visible in the array literal). Verified by building and, at the end of this plan, by a VoiceOver pass in the simulator.

- [ ] **Step 1: Implement `TasteQuizQuestion`**

```swift
import NorseMixologyCore

/// The 5 onboarding quiz questions, presented in this fixed order (no
/// randomisation — see the Phase 11 spec's onboarding checklist). Choosing
/// left sets the axis to 0.85; choosing right sets it to 0.15.
struct TasteQuizQuestion: Identifiable {
    let id: Int
    let axis: WritableKeyPath<UserTasteProfile, Double>
    let leftLabel: String
    let rightLabel: String

    static let all: [TasteQuizQuestion] = [
        TasteQuizQuestion(id: 0, axis: \.sweetness, leftLabel: "Sweet 🍬", rightLabel: "Dry 🍋"),
        TasteQuizQuestion(id: 1, axis: \.bitterness, leftLabel: "Bitter & Bold", rightLabel: "Smooth & Mellow"),
        TasteQuizQuestion(id: 2, axis: \.citrus, leftLabel: "Bright & Citrusy", rightLabel: "Rich & Deep"),
        TasteQuizQuestion(id: 3, axis: \.smokiness, leftLabel: "Smoky & Peaty", rightLabel: "Clean & Crisp"),
        TasteQuizQuestion(id: 4, axis: \.herbal, leftLabel: "Herbal & Botanical", rightLabel: "Simple & Spirit-forward"),
    ]
}
```

- [ ] **Step 2: Implement `ThisOrThatCard`**

```swift
import SwiftUI

/// One quiz question: a two-half card that responds to a left/right drag
/// **and** exposes each half as an independently tappable, VoiceOver-
/// focusable button — never gesture-only (Phase 6 hardening rule).
struct ThisOrThatCard: View {
    enum Choice { case left, right }

    let question: TasteQuizQuestion
    let onChoose: (Choice) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let dragCommitThreshold: CGFloat = 80

    var body: some View {
        HStack(spacing: 1) {
            choiceHalf(.left, label: question.leftLabel)
            choiceHalf(.right, label: question.rightLabel)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DesignTokens.border, lineWidth: 1)
        )
        .offset(x: dragOffset)
        .rotationEffect(.degrees(dragOffset / 20))
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    isDragging = false
                    if value.translation.width > dragCommitThreshold {
                        onChoose(.right)
                    } else if value.translation.width < -dragCommitThreshold {
                        onChoose(.left)
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
        )
        .animation(.interactiveSpring(), value: dragOffset)
    }

    @ViewBuilder
    private func choiceHalf(_ choice: Choice, label: String) -> some View {
        Button {
            onChoose(choice)
        } label: {
            Text(label)
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Double tap to choose")
    }
}

#Preview {
    ThisOrThatCard(question: TasteQuizQuestion.all[0]) { _ in }
        .padding()
        .dsScreenBackground()
}
```

- [ ] **Step 3: Build the app target to confirm it compiles**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios/NorseMixology/Onboarding/TasteQuizQuestion.swift ios/NorseMixology/Onboarding/ThisOrThatCard.swift
git commit -m "iOS: add taste quiz question data and ThisOrThatCard (Phase 11)"
```

---

## Task 6: `TasteOnboardingView`

**Files:**
- Create: `ios/NorseMixology/Onboarding/TasteOnboardingView.swift`

**Interfaces:**
- Consumes: `TasteQuizQuestion.all`, `ThisOrThatCard`/`ThisOrThatCard.Choice` (Task 5); `UserTasteProfile`, `TasteProfileStore` (Tasks 1–2); `DesignTokens`, `.dsText(_:)`, `.dsScreenBackground()` (existing)
- Produces: `struct TasteOnboardingView: View` with `init(isPresentedAsRetake: Bool = false, onComplete: @escaping (UserTasteProfile) -> Void)`. Both the Skip path and the final-answer path call `TasteProfileStore.save(_:)` themselves before invoking `onComplete`, so callers (Task 7's `ContentView`, Task 8's `SettingsView`) only need to react to the resulting profile — they never call `TasteProfileStore.save` themselves.

- [ ] **Step 1: Implement `TasteOnboardingView`**

```swift
import SwiftUI
import NorseMixologyCore

/// The animated 5-question "this-or-that" onboarding quiz. Used both as the
/// full-screen first-run flow (`isPresentedAsRetake: false`, no Cancel
/// button — there is nothing to cancel back to on a fresh install) and as a
/// sheet from Settings' "Retake Quiz" (`isPresentedAsRetake: true`, adds a
/// Cancel button). Swiping the sheet away mid-quiz also leaves the stored
/// profile untouched, since nothing is saved until Skip or the final answer.
struct TasteOnboardingView: View {
    var isPresentedAsRetake: Bool = false
    var onComplete: (UserTasteProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var profile = UserTasteProfile()
    @State private var currentIndex = 0
    @State private var showCelebration = false

    private let questions = TasteQuizQuestion.all

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                DesignTokens.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    if !showCelebration {
                        progressHeader
                    }
                    Spacer()
                    if showCelebration {
                        celebration
                    } else {
                        ThisOrThatCard(question: questions[currentIndex], onChoose: answer)
                            .id(questions[currentIndex].id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )
                    }
                    Spacer()
                }
                .padding(24)

                if !showCelebration {
                    Button("Skip") { skip() }
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(16)
                        .accessibilityHint("Skips the taste quiz and uses a neutral profile")
                }
            }
            .toolbar {
                if isPresentedAsRetake {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(currentIndex + 1) of \(questions.count)")
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
            ProgressView(value: Double(currentIndex), total: Double(questions.count))
                .tint(DesignTokens.accent)
        }
        .accessibilityElement(children: .combine)
    }

    /// Built so the two pieces animate independently via SwiftUI's insertion
    /// transitions (driven by the `withAnimation` spring in `answer()` when
    /// `showCelebration` flips to true) rather than a shared property
    /// binding — this is also the localized spot to swap in a real Lottie
    /// animation later without restructuring the rest of the flow.
    private var celebration: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(DesignTokens.accent)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            Text("You're all set!")
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all set!")
        .onTapGesture { finish() }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func answer(_ choice: ThisOrThatCard.Choice) {
        profile[keyPath: questions[currentIndex].axis] = choice == .left ? 0.85 : 0.15
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if currentIndex < questions.count - 1 {
                currentIndex += 1
            } else {
                profile.hasCompletedOnboarding = true
                showCelebration = true
            }
        }
    }

    private func skip() {
        let skippedProfile = UserTasteProfile(hasCompletedOnboarding: true)
        TasteProfileStore.save(skippedProfile)
        onComplete(skippedProfile)
    }

    private func finish() {
        TasteProfileStore.save(profile)
        onComplete(profile)
    }
}

#Preview {
    TasteOnboardingView { _ in }
}
```

- [ ] **Step 2: Build the app target to confirm it compiles**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/NorseMixology/Onboarding/TasteOnboardingView.swift
git commit -m "iOS: add TasteOnboardingView quiz flow and completion celebration (Phase 11)"
```

---

## Task 7: App root wiring — onboarding gate, migration, Settings tab

**Files:**
- Modify: `ios/NorseMixology/NorseMixologyApp.swift`
- Modify: `ios/NorseMixology/ContentView.swift`

**Interfaces:**
- Consumes: `TasteOnboardingView` (Task 6), `TasteProfileStore`, `UserTasteProfile` (Tasks 1–2), `CabinetItem`, `FavouriteRecipe` (existing SwiftData models), `SettingsView` (Task 8 — this task adds the tab that references it, so implement Task 8's file in the same session before building, or stub-build after Task 8 lands; the plan orders them this way so `ContentView`'s changes and the Settings tab wiring are reviewed together)
- Produces: `ContentView.init(showOnboardingInitially:)`; `AppTab` gains a `.settings` case

**Design note:** The existing-install migration check needs a `ModelContext`, which is available synchronously in `NorseMixologyApp.init()` as `container.mainContext` — that's where `favouritesViewModel` is already built the same way. Resolving the onboarding decision there (rather than in `ContentView.onAppear`) avoids a visible flash of the tab bar before the quiz appears.

- [ ] **Step 1: Modify `NorseMixologyApp.swift`**

Change:

```swift
    init() {
        // The container is built explicitly (rather than via `.modelContainer(for:)`)
        // so the app-wide `FavouritesViewModel` can share its main context.
        do {
            let container = try ModelContainer(for: CabinetItem.self, FavouriteRecipe.self)
            modelContainer = container
            _favouritesViewModel = State(initialValue: FavouritesViewModel(modelContext: container.mainContext))
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(taxonomyStore)
                .environment(favouritesViewModel)
                .task {
                    loadBundledTaxonomyAndLog()
                }
        }
        .modelContainer(modelContainer)
    }
```

to:

```swift
    @State private var showOnboardingInitially: Bool

    init() {
        // The container is built explicitly (rather than via `.modelContainer(for:)`)
        // so the app-wide `FavouritesViewModel` can share its main context.
        do {
            let container = try ModelContainer(for: CabinetItem.self, FavouriteRecipe.self)
            modelContainer = container
            _favouritesViewModel = State(initialValue: FavouritesViewModel(modelContext: container.mainContext))
            _showOnboardingInitially = State(initialValue: Self.resolveShowOnboarding(context: container.mainContext))
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showOnboardingInitially: showOnboardingInitially)
                .environment(taxonomyStore)
                .environment(favouritesViewModel)
                .task {
                    loadBundledTaxonomyAndLog()
                }
        }
        .modelContainer(modelContainer)
    }

    /// Fresh installs see the quiz. An existing install that already has
    /// cabinet or favourite data (but never completed the quiz, since it
    /// predates this phase) silently gets a neutral *completed* profile
    /// instead — only genuinely fresh installs see the onboarding flow.
    private static func resolveShowOnboarding(context: ModelContext) -> Bool {
        let profile = TasteProfileStore.load()
        guard !profile.hasCompletedOnboarding else { return false }

        let hasCabinetItems = ((try? context.fetchCount(FetchDescriptor<CabinetItem>())) ?? 0) > 0
        let hasFavourites = ((try? context.fetchCount(FetchDescriptor<FavouriteRecipe>())) ?? 0) > 0
        guard hasCabinetItems || hasFavourites else { return true }

        TasteProfileStore.save(UserTasteProfile(hasCompletedOnboarding: true))
        return false
    }
```

- [ ] **Step 2: Modify `ContentView.swift`**

Change:

```swift
enum AppTab: Hashable {
    case recipes, cabinet, favourites
}

/// Root: `TabView` with a `NavigationStack` per screen. The Recipes tab adapts
/// itself to a list/detail split at regular width.
struct ContentView: View {
    @State private var selectedTab: AppTab = .recipes
    @State private var recipeBrowserViewModel = RecipeBrowserViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            RecipeBrowserView()
                .tabItem { Label("Recipes", systemImage: "wineglass") }
                .tag(AppTab.recipes)

            CabinetView(onFindRecipes: { selectedTab = .recipes })
                .tabItem { Label("Cabinet", systemImage: "archivebox") }
                .tag(AppTab.cabinet)

            FavouritesView()
                .tabItem { Label("Favourites", systemImage: "heart") }
                .tag(AppTab.favourites)
        }
        .environment(recipeBrowserViewModel)
    }
}
```

to:

```swift
enum AppTab: Hashable {
    case recipes, cabinet, favourites, settings
}

/// Root: shows the taste quiz before the first launch's `TabView` (unless an
/// existing install already had cabinet/favourite data — see
/// `NorseMixologyApp.resolveShowOnboarding`), then a `TabView` with a
/// `NavigationStack` per screen. The Recipes tab adapts itself to a
/// list/detail split at regular width.
struct ContentView: View {
    @State private var selectedTab: AppTab = .recipes
    @State private var recipeBrowserViewModel = RecipeBrowserViewModel()
    @State private var showOnboarding: Bool

    init(showOnboardingInitially: Bool) {
        _showOnboarding = State(initialValue: showOnboardingInitially)
    }

    var body: some View {
        Group {
            if showOnboarding {
                TasteOnboardingView { _ in
                    withAnimation { showOnboarding = false }
                }
            } else {
                tabs
            }
        }
        .environment(recipeBrowserViewModel)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            RecipeBrowserView()
                .tabItem { Label("Recipes", systemImage: "wineglass") }
                .tag(AppTab.recipes)

            CabinetView(onFindRecipes: { selectedTab = .recipes })
                .tabItem { Label("Cabinet", systemImage: "archivebox") }
                .tag(AppTab.cabinet)

            FavouritesView()
                .tabItem { Label("Favourites", systemImage: "heart") }
                .tag(AppTab.favourites)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
```

Also update the `#Preview` at the bottom of `ContentView.swift` to pass the new required argument:

```swift
#Preview {
    if let container = try? ModelContainer(
        for: CabinetItem.self, FavouriteRecipe.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
        ContentView(showOnboardingInitially: false)
            .environment(TaxonomyStore())
            .environment(FavouritesViewModel(modelContext: container.mainContext))
            .modelContainer(container)
    } else {
        Text("Couldn't create the preview data container")
    }
}
```

- [ ] **Step 3: Build the app target**

This will not yet succeed — `SettingsView` doesn't exist until Task 8. Confirm the *only* build error is the missing `SettingsView` symbol (no other errors), then proceed to Task 8 before committing this task.

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: build fails with exactly one error class: `cannot find 'SettingsView' in scope`

- [ ] **Step 4: Commit (staged together with Task 8 once the build succeeds)**

Hold this commit — it will be made jointly with Task 8's Step 3 below, since `ContentView.swift` doesn't compile without `SettingsView`.

---

## Task 8: `SettingsView`

**Files:**
- Create: `ios/NorseMixology/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `TasteOnboardingView` (Task 6); `TasteProfileStore`, `UserTasteProfile` (Tasks 1–2); `FlavorProfileIndicatorView` (existing, `Components/FlavorProfileIndicatorView.swift`) — takes a full `FlavorProfile`, but only ever reads/displays its `sweetness`/`bitterness`/`smokiness`/`citrus`/`herbal` fields and `accessibilitySummary` (also only those 5), so this view can safely reuse it by filling the un-quizzed `FlavorProfile` fields with `0` — those values are never read
- Produces: `struct SettingsView: View`

- [ ] **Step 1: Implement `SettingsView`**

```swift
import SwiftUI
import NorseMixologyCore

/// The Settings tab: shows the saved taste profile read-only and offers
/// "Retake Quiz", which presents `TasteOnboardingView` as a sheet.
/// Cancelling the sheet leaves the stored profile untouched; completing it
/// overwrites the profile shown here.
struct SettingsView: View {
    @State private var profile = TasteProfileStore.load()
    @State private var isRetakingQuiz = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Taste") {
                    VStack(alignment: .leading, spacing: 8) {
                        FlavorProfileIndicatorView(profile: displayFlavorProfile)
                        Text(profile.hasCompletedOnboarding ? "Based on your taste quiz answers." : "You haven't taken the taste quiz yet.")
                            .dsText(.body)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .listRowBackground(DesignTokens.surface)
                }

                Section {
                    Button("Retake Quiz") { isRetakingQuiz = true }
                        .listRowBackground(DesignTokens.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .navigationTitle("Settings")
        }
        .onAppear { profile = TasteProfileStore.load() }
        .sheet(isPresented: $isRetakingQuiz) {
            TasteOnboardingView(isPresentedAsRetake: true) { updated in
                profile = updated
                isRetakingQuiz = false
            }
        }
    }

    /// `FlavorProfileIndicatorView` only ever reads sweetness/bitterness/
    /// smokiness/citrus/herbal (see its `values` and `FlavorProfile.
    /// accessibilitySummary`), so the un-quizzed fields below are filler
    /// that is never displayed — this is display-only reuse, not a
    /// comparison, so it doesn't violate the "never default and compare
    /// un-quizzed axes" rule.
    private var displayFlavorProfile: FlavorProfile {
        FlavorProfile(
            sweetness: profile.sweetness, bitterness: profile.bitterness, smokiness: profile.smokiness,
            citrus: profile.citrus, floral: 0, spice: 0, herbal: profile.herbal, fruity: 0, oaky: 0, abv: 0
        )
    }
}

#Preview {
    SettingsView()
}
```

- [ ] **Step 2: Build the app target to confirm both Task 7 and Task 8 compile together**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit Tasks 7 and 8 together**

```bash
git add ios/NorseMixology/NorseMixologyApp.swift ios/NorseMixology/ContentView.swift ios/NorseMixology/Settings/SettingsView.swift
git commit -m "iOS: wire onboarding gate, migration check, and Settings tab (Phase 11)"
```

---

## Task 9: Manual verification pass

No further code changes in this task — only running the app in the simulator against the Phase 11 spec's Verification checklist. Use the already-booted "iPhone 17 Pro" simulator (`mcp__Claude_Code_iOS_Simulator__control`, or Xcode directly).

- [ ] **Step 1: Fresh-install quiz flow**

Erase the simulator's app data (Xcode: long-press app icon → Remove App, or `xcrun simctl uninstall <udid> <bundle-id>`), relaunch, and confirm: the quiz appears before the tab bar; dragging or tapping through all 5 cards shows the "N of 5" counter and progress bar advancing; the 5th answer shows the checkmark celebration; it auto-dismisses (or dismisses on tap) into the Recipes tab.

- [ ] **Step 2: Skip path**

Reinstall fresh, launch, tap Skip immediately. Confirm: no celebration, lands directly on the Recipes tab, and the Recipe Browser's ranking is unchanged from Phase 4/6 behaviour (no visible reordering effect).

- [ ] **Step 3: Existing-install migration**

Since the quiz blocks the tab bar, "add cabinet data before completing the quiz" isn't reachable through the UI — instead verify the migration path directly. With the app already installed and having some cabinet data (e.g. from Step 1 or 2), force-quit it, then clear just the taste-profile key so the app believes onboarding was never completed:

```bash
xcrun simctl spawn "iPhone 17 Pro" defaults delete dev.martinloeseth.NorseMixology com.norsemixology.userTasteProfile
```

Relaunch. Confirm the quiz does **not** reappear (because `CabinetItem`/`FavouriteRecipe` rows already exist) and the Settings tab shows a neutral, completed profile.

- [ ] **Step 4: Ranking effect on tied Perfect Matches**

Build a cabinet that produces 2+ tied Perfect Match recipes (matchScore == 1.0 for both). Complete the quiz leaning strongly toward one recipe's flavour profile (e.g. answer "Sweet" if one of the tied recipes is noticeably sweeter). Confirm the Recipes tab's Perfect Match section now shows that recipe first.

- [ ] **Step 5: Settings retake flow**

Go to Settings, confirm the taste dots and summary match the profile from Step 4. Tap Retake Quiz, answer differently, complete it. Confirm Settings updates immediately and the Recipes tab (after revisiting it) reflects the new order. Retake again and tap Cancel partway through — confirm Settings' displayed profile is unchanged.

- [ ] **Step 6: Accessibility**

Enable VoiceOver in the simulator (or use `control` → `inspect` to read the accessibility tree). Confirm each quiz card's two halves are independently focusable with their label text, Skip and Cancel are reachable and labeled, and the Settings taste summary reads as "Sweetness: high, Bitterness: low, …" per `FlavorProfile.accessibilitySummary`.

- [ ] **Step 7: Large Dynamic Type**

Set the simulator's text size to the largest accessibility size (Settings → Accessibility → Display & Text Size → Larger Text). Confirm quiz card text wraps rather than truncating, and the progress header/Skip/Cancel buttons remain usable.

- [ ] **Step 8: Update the Obsidian phase doc**

Edit `Phases/Phase 11 - iOS Taste Profile & Animated Onboarding.md`'s Status line and check off every checklist/Verification item confirmed above, following the same pattern as Phases 6 and 10's Status lines (what was verified, what's outstanding, any deviations found and why).

- [ ] **Step 9: Merge**

Once verification is complete and the phase doc is updated, merge `phase-11-ios-taste-profile-onboarding` back to `main` (fast-forward, per this project's established branch-per-phase convention) and update `Overview.md`'s status line and Build Phases table row for Phase 11 to done.
