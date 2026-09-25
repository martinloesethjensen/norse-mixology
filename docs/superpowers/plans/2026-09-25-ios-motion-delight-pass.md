# iOS Motion & Delight Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native SwiftUI motion to Recipe Browser, Cabinet, and shared components — one signature "hero" reveal for the Perfect Match badge, a staggered tier/card entrance, a sequential flavour-dot fill, cabinet insertion feedback, and a floating empty-state icon — without touching the matching engine, `TasteRanking`, or tier partitioning.

**Architecture:** All changes are presentation-only, inside the `NorseMixology` app target (no `NorseMixologyCore` changes). `RecipeBrowserViewModel` gains a small `revealedResultIds: Set<UUID>` to track which results have already played their entrance/hero animation, cleared only when the actual match result set changes (not on every tab revisit). `RecipeCardView` and `MatchBadgeView` read that state to decide whether to animate. A new small shared `FloatingIcon` view replaces the bare `Image`/`Label` inside three `ContentUnavailableView`s so their icon (not their title, description, or action button) can idle-float. Every new animation is gated behind `@Environment(\.accessibilityReduceMotion)`, following the existing inline-check convention already used in `RecipeDetailView.swift` and `IngredientRowView.swift` (no new shared modifier for that — this project doesn't have one and doesn't need one for six call sites).

**Tech Stack:** Swift 5.9, SwiftUI, native `.spring`/`.easeOut` animations (no Lottie, no new dependency).

**Spec:** `Phases/Phase 12 - iOS Motion & Delight Pass.md` in the Obsidian vault (`/Users/mlj/Library/Mobile Documents/iCloud~md~obsidian/Documents/Project Ideas/Dev Project Ideas/Norse Mixology/Phases/Phase 12 - iOS Motion & Delight Pass.md`)

**Deviations from that spec, decided while writing this plan against the real code** (the spec was written from the Design System doc's intent, not the shipped implementation — flag these in the phase doc's Notes once built, same as Phase 11's "wording clarification" and "built differently" notes):
- There are no "Cabinet Chips" in the shipped app — ingredients are added via `AddIngredientView`'s search/browse list → `AddIngredientConfirmationView` sheet, not a toggleable chip grid. The real "feedback" moments are: `IngredientRow`'s checkmark appearing once a style is in the cabinet, and the new row settling into `CabinetView`'s `List`.
- `MatchBadgeView` renders a text label on a solid pill (`"✓ All ingredients"` / `"1 sub needed"`), not a numeric score — there is no score to "fill to." The Almost There / Worth Exploring badges get a plain materialize-in (scale + opacity) instead of an invented progress fill. Only the Perfect Match badge gets the sweep, since it alone is the hero.
- The "liquid fill sweep" is built as a one-shot diagonal highlight sweeping across the already-lime-filled capsule, not a 0→full colour fill. Filling from literally transparent would leave the dark badge text low-contrast against the screen background for part of the animation — a highlight sweep reads as "catching the light as it settles" without that contrast dip.
- Empty-state illustrations don't exist yet (`ContentUnavailableView` uses a plain SF Symbol) — the float applies to that symbol only, via `ContentUnavailableView`'s closure-based `label:` initializer instead of the string convenience initializer, so the icon can be isolated from title/description/action.
- Cabinet's ingredient-added settle-in is implemented as specced, but note for the phase doc: because adding happens inside `AddIngredientConfirmationView`'s sheet and the sheet's own dismiss animation covers the moment the row appears, this animation is mostly imperceptible in the current flow. Built anyway for correctness/consistency (and because a future direct-add flow would surface it) — not a wasted task, just a lower-impact one than the spec assumed.

## Global Constraints

- **Never modify** anything under `Packages/NorseMixologyCore/` — this phase is app-target-only, presentation logic never touches matching/ranking.
- Every new animation must check `@Environment(\.accessibilityReduceMotion)` and skip straight to the end state when true — follow the existing inline pattern, don't add a new abstraction.
- No Lottie, no new SPM dependency.
- `RecipeBrowserViewModel`'s public surface (`results`, `grouped`, `cabinetStyleIds`, `selectedRecipeID`, `perfectMatches`/`almostMatches`/`explorationMatches`, `refresh(...)`) keeps its existing signatures — only new members are added.
- This phase is iOS-only. Do not touch anything under `android/`.

---

## File Structure

**New files:**
- `ios/NorseMixology/Components/FloatingIcon.swift` — the shared idle-float icon wrapper for empty states

**Modified files:**
- `ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift` — add `revealedResultIds` tracking
- `ios/NorseMixology/Recipes/MatchBadgeView.swift` — add the hero shine-sweep for Perfect Match
- `ios/NorseMixology/Recipes/RecipeCardView.swift` — staggered entrance + hero scale-pulse, wires reveal tracking
- `ios/NorseMixology/Recipes/RecipeResultsList.swift` — per-tier reveal delay, empty-state icon float
- `ios/NorseMixology/Components/FlavorProfileIndicatorView.swift` — sequential dot fill-in
- `ios/NorseMixology/Cabinet/CabinetView.swift` — animated row insertion, empty-state icon float
- `ios/NorseMixology/Cabinet/IngredientRow.swift` — checkmark materialize transition
- `ios/NorseMixology/Favourites/FavouritesView.swift` — empty-state icon float

---

## Task 1: `RecipeBrowserViewModel` reveal tracking

**Files:**
- Modify: `ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift`

**Interfaces:**
- Produces: `func hasBeenRevealed(_ id: UUID) -> Bool`, `func markRevealed(_ id: UUID)` on `RecipeBrowserViewModel`

**Design note:** Cleared only when the *set* of result ids actually changes (a real re-match), not on every `refresh()` call — a tab revisit that re-runs `refresh()` against an unchanged cabinet must not replay every card's entrance animation. Comparing `Set<UUID>` equality before assigning `results` is the simplest correct check.

- [ ] **Step 1: Modify `RecipeBrowserViewModel.swift`**

Change:

```swift
    /// Re-runs the match against the cabinet currently in SwiftData.
    func refresh(context: ModelContext, taxonomyStore: TaxonomyStore) {
        refresh(cabinet: CabinetService.allItems(context: context), taxonomyStore: taxonomyStore)
    }

    func refresh(cabinet: [CabinetItem], taxonomyStore: TaxonomyStore) {
        results = RecipeService.findRecipes(
            for: cabinet,
            recipes: taxonomyStore.recipes,
            taxonomyCategories: taxonomyStore.categories
        )
        grouped = GroupedMatchResults(results: results)
        grouped = TasteRanking.reorder(grouped, toward: TasteProfileStore.load())
        cabinetStyleIds = Set(cabinet.map(\.ingredientStyleId))

        // A recipe can drop out of the results when the cabinet changes.
        if let selectedRecipeID, !results.contains(where: { $0.id == selectedRecipeID }) {
            self.selectedRecipeID = nil
        }
    }
}
```

to:

```swift
    /// Re-runs the match against the cabinet currently in SwiftData.
    func refresh(context: ModelContext, taxonomyStore: TaxonomyStore) {
        refresh(cabinet: CabinetService.allItems(context: context), taxonomyStore: taxonomyStore)
    }

    func refresh(cabinet: [CabinetItem], taxonomyStore: TaxonomyStore) {
        let newResults = RecipeService.findRecipes(
            for: cabinet,
            recipes: taxonomyStore.recipes,
            taxonomyCategories: taxonomyStore.categories
        )

        // Only a genuine change in which recipes matched should replay each
        // card's entrance/hero animation — revisiting the Recipes tab with an
        // unchanged cabinet must not re-animate cards already shown.
        if Set(newResults.map(\.id)) != Set(results.map(\.id)) {
            revealedResultIds.removeAll()
        }

        results = newResults
        grouped = GroupedMatchResults(results: results)
        grouped = TasteRanking.reorder(grouped, toward: TasteProfileStore.load())
        cabinetStyleIds = Set(cabinet.map(\.ingredientStyleId))

        // A recipe can drop out of the results when the cabinet changes.
        if let selectedRecipeID, !results.contains(where: { $0.id == selectedRecipeID }) {
            self.selectedRecipeID = nil
        }
    }

    /// Whether `id` has already played its Recipe Browser entrance/hero
    /// animation this "generation" of results — see `refresh`'s id-set check.
    /// Used so `LazyVStack` recycling rows during scroll doesn't replay a
    /// card's fade-in or the Perfect Match sweep every time it scrolls back
    /// into view.
    func hasBeenRevealed(_ id: UUID) -> Bool {
        revealedResultIds.contains(id)
    }

    func markRevealed(_ id: UUID) {
        revealedResultIds.insert(id)
    }
}
```

Also add the stored property near the other `private(set) var` declarations:

```swift
    private(set) var revealedResultIds: Set<UUID> = []
```

- [ ] **Step 2: Build the app target to confirm it compiles**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/NorseMixology/Recipes/RecipeBrowserViewModel.swift
git commit -m "iOS: track revealed Recipe Browser results (Phase 12)"
```

---

## Task 2: Perfect Match hero reveal + staggered card entrance

**Files:**
- Modify: `ios/NorseMixology/Recipes/MatchBadgeView.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeCardView.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeResultsList.swift`

**Interfaces:**
- Consumes: `RecipeBrowserViewModel.hasBeenRevealed(_:)` / `.markRevealed(_:)` (Task 1)
- Produces: `MatchBadgeView(state:playHeroSweep:)` (new `playHeroSweep: Bool = false` parameter); `RecipeCardView(result:isSelected:revealDelay:)` (new `revealDelay: Double = 0` parameter)

**Design note:** The sweep is a one-shot diagonal white highlight (`.mask(Capsule())`, animated `x` offset from off-badge-left to off-badge-right, ~350ms `.easeOut`) layered over the badge's existing lime fill — not a 0→full colour fill (see plan header's Deviations). It only plays when `playHeroSweep` is true, which `RecipeCardView` sets to `result.matchType == .exact && isFirstReveal`. The whole-card scale pulse (1.0 → 1.02 → 1.0) starts right as the sweep finishes. The staggered fade+offset entrance applies to every card (all three tiers), using `revealDelay` computed by `RecipeResultsList` per tier/index; `RecipeCardView` marks itself revealed on first appearance so re-scrolling never replays it.

- [ ] **Step 1: Add the hero sweep to `MatchBadgeView`**

Change:

```swift
struct MatchBadgeView: View {
    let state: MatchBadgeState

    var body: some View {
        Text(state.label)
            .dsText(.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(DesignTokens.onBadge)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(state.color))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state == .exact ? "All ingredients in your cabinet" : state.label)
    }
}
```

to:

```swift
struct MatchBadgeView: View {
    let state: MatchBadgeState
    /// Plays a one-shot diagonal highlight sweep across the badge — reserved
    /// for a recipe's first appearance as a Perfect Match (see
    /// `RecipeCardView`). Never set for Almost There / Worth Exploring: there
    /// is no numeric score on this badge to "fill," only a hero moment for
    /// the one tier that represents "you can make this right now."
    var playHeroSweep = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepProgress: CGFloat = 0

    var body: some View {
        Text(state.label)
            .dsText(.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(DesignTokens.onBadge)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(state.color))
            .overlay(sweepHighlight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state == .exact ? "All ingredients in your cabinet" : state.label)
            .onAppear(perform: startSweepIfNeeded)
    }

    @ViewBuilder
    private var sweepHighlight: some View {
        if playHeroSweep, !reduceMotion {
            GeometryReader { proxy in
                let width = proxy.size.width
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: width * 0.6)
                .offset(x: -width * 0.6 + sweepProgress * width * 1.6)
            }
            .mask(Capsule())
            .allowsHitTesting(false)
        }
    }

    private func startSweepIfNeeded() {
        guard playHeroSweep, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            sweepProgress = 1
        }
    }
}
```

- [ ] **Step 2: Wire the hero pulse and staggered entrance into `RecipeCardView`**

Change:

```swift
struct RecipeCardView: View {
    let result: RecipeMatchResult
    var isSelected = false

    @Environment(FavouritesViewModel.self) private var favourites

    private var recipe: Recipe { result.recipe }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
```

to:

```swift
struct RecipeCardView: View {
    let result: RecipeMatchResult
    var isSelected = false
    /// How long to wait before this card's entrance animation starts —
    /// computed by `RecipeResultsList` from the card's tier and position, so
    /// Perfect Match arrives first and each tier staggers in after it.
    var revealDelay: Double = 0

    @Environment(FavouritesViewModel.self) private var favourites
    @Environment(RecipeBrowserViewModel.self) private var browserViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false
    @State private var isPulsing = false

    private var recipe: Recipe { result.recipe }
    private var isPerfectMatch: Bool { result.matchType == .exact }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
```

Then, immediately after the `MatchBadgeView(state: MatchBadgeState(result: result))` line inside the `VStack`, change it to:

```swift
            MatchBadgeView(state: MatchBadgeState(result: result), playHeroSweep: isPerfectMatch && isFirstReveal)
```

Add `isFirstReveal` as a computed property near `isPerfectMatch`:

```swift
    private var isFirstReveal: Bool { !browserViewModel.hasBeenRevealed(result.id) }
```

Finally, change the view's modifier chain (currently ending at `.accessibilityElement(children: .combine)`) and add the reveal lifecycle:

```swift
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? DesignTokens.accent : DesignTokens.border, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .scaleEffect(isPulsing ? 1.02 : 1)
        .opacity(reduceMotion || hasAppeared ? 1 : 0)
        .offset(y: reduceMotion || hasAppeared ? 0 : 8)
        .onAppear(perform: reveal)
    }

    private func reveal() {
        let wasAlreadyRevealed = browserViewModel.hasBeenRevealed(result.id)
        browserViewModel.markRevealed(result.id)

        guard !reduceMotion, !wasAlreadyRevealed else {
            hasAppeared = true
            return
        }

        withAnimation(.easeOut(duration: 0.3).delay(revealDelay)) {
            hasAppeared = true
        }

        guard isPerfectMatch else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((revealDelay + 0.35) * 1000)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = true }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = false }
        }
    }
}
```

- [ ] **Step 3: Compute per-tier reveal delay in `RecipeResultsList`**

Change:

```swift
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    section("🍹 Perfect Match", subtitle: "You have everything", matches: grouped.perfect)
                    section("🔄 Almost There", subtitle: "Missing 1 ingredient", matches: grouped.almost)
                    section("🔍 Worth Exploring", subtitle: "Needs a few subs", matches: grouped.exploring)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .dsScreenBackground()
            .refreshable { onRefresh() }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringResource, subtitle: LocalizedStringResource, matches: [RecipeMatchResult]) -> some View {
        if !matches.isEmpty {
            Section {
                ForEach(matches) { result in
                    card(for: result)
                }
            } header: {
```

to:

```swift
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    section("🍹 Perfect Match", subtitle: "You have everything", matches: grouped.perfect, tierDelay: 0)
                    section("🔄 Almost There", subtitle: "Missing 1 ingredient", matches: grouped.almost, tierDelay: 0.08)
                    section("🔍 Worth Exploring", subtitle: "Needs a few subs", matches: grouped.exploring, tierDelay: 0.16)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .dsScreenBackground()
            .refreshable { onRefresh() }
        }
    }

    /// Within a tier, only the first 6 cards stagger individually (~40ms
    /// apart) — a long tier's remaining cards all arrive together at that
    /// cap, so a 150-result list doesn't take visibly long to finish
    /// revealing.
    private let maxStaggeredIndex = 6
    private let staggerStep = 0.04

    @ViewBuilder
    private func section(_ title: LocalizedStringResource, subtitle: LocalizedStringResource, matches: [RecipeMatchResult], tierDelay: Double) -> some View {
        if !matches.isEmpty {
            Section {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, result in
                    let delay = tierDelay + Double(min(index, maxStaggeredIndex)) * staggerStep
                    card(for: result, revealDelay: delay)
                }
            } header: {
```

Then update `card(for:)`'s signature and both call sites inside it:

```swift
    @ViewBuilder
    private func card(for result: RecipeMatchResult) -> some View {
        switch interaction {
        case .push:
            NavigationLink(value: result.id) {
                RecipeCardView(result: result)
            }
            .buttonStyle(.plain)
        case .select(let selectedID, let onSelect):
            Button {
                onSelect(result.id)
            } label: {
                RecipeCardView(result: result, isSelected: result.id == selectedID)
            }
            .buttonStyle(.plain)
        }
    }
```

to:

```swift
    @ViewBuilder
    private func card(for result: RecipeMatchResult, revealDelay: Double) -> some View {
        switch interaction {
        case .push:
            NavigationLink(value: result.id) {
                RecipeCardView(result: result, revealDelay: revealDelay)
            }
            .buttonStyle(.plain)
        case .select(let selectedID, let onSelect):
            Button {
                onSelect(result.id)
            } label: {
                RecipeCardView(result: result, isSelected: result.id == selectedID, revealDelay: revealDelay)
            }
            .buttonStyle(.plain)
        }
    }
```

- [ ] **Step 4: Build the app target**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/NorseMixology/Recipes/MatchBadgeView.swift ios/NorseMixology/Recipes/RecipeCardView.swift ios/NorseMixology/Recipes/RecipeResultsList.swift
git commit -m "iOS: Perfect Match hero sweep and staggered card entrance (Phase 12)"
```

---

## Task 3: Sequential flavour-dot fill

**Files:**
- Modify: `ios/NorseMixology/Components/FlavorProfileIndicatorView.swift`

**Interfaces:** No signature change — `FlavorProfileIndicatorView(profile:)` stays the same; the animation is internal.

**Design note:** Each dot fades/scales in with a ~60ms stagger on first appearance. This view is used inside `List` rows (`CabinetItemRow`, `IngredientRow`, `AddIngredientConfirmationView`) that can be recreated during scroll, so an occasional replay during fast scrolling is possible — accepted as a low-severity cosmetic tradeoff rather than building a full reveal-tracking system (like Task 1's) for a component this small; note this in the phase doc rather than silently shipping it unmentioned.

- [ ] **Step 1: Modify `FlavorProfileIndicatorView`**

Change:

```swift
struct FlavorProfileIndicatorView: View {
    let profile: FlavorProfile

    private var values: [Double] {
        [profile.sweetness, profile.bitterness, profile.smokiness, profile.citrus, profile.herbal]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Circle()
                    .fill(DesignTokens.accent.opacity(0.15 + value * 0.85))
                    .overlay(Circle().strokeBorder(DesignTokens.border, lineWidth: 0.5))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flavour profile")
        .accessibilityValue(profile.accessibilitySummary)
    }
}
```

to:

```swift
struct FlavorProfileIndicatorView: View {
    let profile: FlavorProfile

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var values: [Double] {
        [profile.sweetness, profile.bitterness, profile.smokiness, profile.citrus, profile.herbal]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Circle()
                    .fill(DesignTokens.accent.opacity(0.15 + value * 0.85))
                    .overlay(Circle().strokeBorder(DesignTokens.border, lineWidth: 0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.4)
                    .opacity(reduceMotion || hasAppeared ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(Double(index) * 0.06), value: hasAppeared)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flavour profile")
        .accessibilityValue(profile.accessibilitySummary)
        .onAppear { hasAppeared = true }
    }
}
```

- [ ] **Step 2: Build the app target**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/NorseMixology/Components/FlavorProfileIndicatorView.swift
git commit -m "iOS: sequential flavour-dot fill-in (Phase 12)"
```

---

## Task 4: Cabinet insertion feedback

**Files:**
- Modify: `ios/NorseMixology/Cabinet/CabinetView.swift`
- Modify: `ios/NorseMixology/Cabinet/IngredientRow.swift`

**Interfaces:** No signature changes to either view.

**Design note:** `List` animates row insertion/removal automatically when the underlying data change happens inside `withAnimation` — `CabinetViewModel.add`/`.remove` call `refresh()` directly with no animation today. Wrapping just the `items`/`refresh()` mutation (not the whole view model) keeps this a one-line, low-risk change. `IngredientRow`'s checkmark gets a scale+opacity transition so it materializes rather than popping in when `isInCabinet` flips from false to true (visible when returning from the Add Ingredient sheet to an unchanged search list, or in `BrowseTaxonomyView` if it re-renders the same row).

- [ ] **Step 1: Animate row insertion in `CabinetViewModel`**

`CabinetViewModel` is not a View, so it can't call `withAnimation` on behalf of the caller — instead, animate in `CabinetView` around the point where `viewModel.groupedItems` changes. The simplest correct hook is `CabinetItem`'s row `.transition`, driven by `List`'s own diffing, which requires no `withAnimation` call at all as long as the transition modifier is present — add it directly:

In `CabinetView.swift`, change:

```swift
                List {
                    ForEach(viewModel.groupedItems, id: \.category) { group in
                        Section {
                            ForEach(group.items) { item in
                                CabinetItemRow(item: item)
                                    .listRowBackground(DesignTokens.surface)
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    viewModel.remove(group.items[index])
                                }
                            }
                        } header: {
```

to:

```swift
                List {
                    ForEach(viewModel.groupedItems, id: \.category) { group in
                        Section {
                            ForEach(group.items) { item in
                                CabinetItemRow(item: item)
                                    .listRowBackground(DesignTokens.surface)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    viewModel.remove(group.items[index])
                                }
                            }
                        } header: {
```

Then, in `CabinetViewModel.swift`, wrap the two call sites that mutate `items` via `refresh()` so `List` actually animates the transition instead of snapping instantly. Change:

```swift
    func add(_ style: IngredientStyle, taxonomyStore: TaxonomyStore, brand: String? = nil) {
        guard !contains(styleId: style.id) else { return }
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandValue = (trimmedBrand?.isEmpty ?? true) ? nil : trimmedBrand
        let item = CabinetItem(
            ingredientStyleId: style.id,
            ingredientFamilyId: style.familyId,
            categoryId: style.categoryId,
            displayName: brandValue.map { "\($0) \(style.name)" } ?? style.name,
            brand: brandValue,
            style: style.name,
            family: taxonomyStore.familyNamesById[style.familyId] ?? "",
            category: taxonomyStore.categoryNamesById[style.categoryId] ?? "",
            flavorProfile: style.flavorProfile
        )
        CabinetService.add(item, context: modelContext)
        refresh()
    }
```

to:

```swift
    func add(_ style: IngredientStyle, taxonomyStore: TaxonomyStore, brand: String? = nil) {
        guard !contains(styleId: style.id) else { return }
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandValue = (trimmedBrand?.isEmpty ?? true) ? nil : trimmedBrand
        let item = CabinetItem(
            ingredientStyleId: style.id,
            ingredientFamilyId: style.familyId,
            categoryId: style.categoryId,
            displayName: brandValue.map { "\($0) \(style.name)" } ?? style.name,
            brand: brandValue,
            style: style.name,
            family: taxonomyStore.familyNamesById[style.familyId] ?? "",
            category: taxonomyStore.categoryNamesById[style.categoryId] ?? "",
            flavorProfile: style.flavorProfile
        )
        CabinetService.add(item, context: modelContext)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            refresh()
        }
    }
```

`CabinetViewModel` has no `accessibilityReduceMotion` access (it's not a View) — that's fine, because `.transition` on the row is a no-op if the row was never absent, and SwiftUI already collapses transition animations under Reduce Motion system-wide for standard transitions (`.scale`, `.opacity`) without needing an explicit check, unlike the custom sweep/pulse in Task 2 which use bespoke `withAnimation` calls and do need the explicit guard.

- [ ] **Step 2: Materialize the checkmark in `IngredientRow`**

Change:

```swift
struct IngredientRow: View {
    let style: IngredientStyle
    let familyName: String
    let isInCabinet: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                if !style.exampleBrands.isEmpty {
                    Text(style.exampleBrands.prefix(2).joined(separator: ", "))
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Spacer()
            FlavorProfileIndicatorView(profile: style.flavorProfile)
            if isInCabinet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.matchExact)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isInCabinet ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isInCabinet ? "Already in your cabinet" : "")
    }
}
```

to:

```swift
struct IngredientRow: View {
    let style: IngredientStyle
    let familyName: String
    let isInCabinet: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                if !style.exampleBrands.isEmpty {
                    Text(style.exampleBrands.prefix(2).joined(separator: ", "))
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Spacer()
            FlavorProfileIndicatorView(profile: style.flavorProfile)
            if isInCabinet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.matchExact)
                    .accessibilityHidden(true)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .opacity(isInCabinet ? 0.5 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isInCabinet)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isInCabinet ? "Already in your cabinet" : "")
    }
}
```

- [ ] **Step 3: Build the app target**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios/NorseMixology/Cabinet/CabinetView.swift ios/NorseMixology/Cabinet/CabinetViewModel.swift ios/NorseMixology/Cabinet/IngredientRow.swift
git commit -m "iOS: animate cabinet insertion and checkmark materialize (Phase 12)"
```

---

## Task 5: Floating empty-state icon

**Files:**
- Create: `ios/NorseMixology/Components/FloatingIcon.swift`
- Modify: `ios/NorseMixology/Cabinet/CabinetView.swift`
- Modify: `ios/NorseMixology/Favourites/FavouritesView.swift`
- Modify: `ios/NorseMixology/Recipes/RecipeResultsList.swift`

**Interfaces:**
- Produces: `struct FloatingIcon: View` with `init(systemName: String)`

**Design note:** `ContentUnavailableView`'s string convenience initializer (`ContentUnavailableView("title", systemImage:, description:)`) can't be reached into to animate just the icon — its closure-based initializer (`label:`/`description:`/`actions:`) can. Switching to the closure form and passing `FloatingIcon` as the label's icon isolates the float to the icon alone; title, description, and (for Cabinet's empty state) the action button stay still. The float is a small, slow, looping vertical drift (±2.5pt, ~3s) — under Reduce Motion it freezes on its resting frame rather than being removed, so the icon doesn't look broken or oddly offset.

- [ ] **Step 1: Create `FloatingIcon`**

```swift
import SwiftUI

/// A system-symbol icon with a slow, looping vertical drift — used inside
/// empty states (`ContentUnavailableView`'s closure-based `label:`) so the
/// float is isolated to the icon and never touches title/description/action
/// text. Freezes at rest under Reduce Motion rather than being removed, so
/// the icon doesn't look mid-animation or offset.
struct FloatingIcon: View {
    let systemName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        Image(systemName: systemName)
            .offset(y: isFloating ? -2.5 : 2.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    isFloating = true
                }
            }
    }
}
```

- [ ] **Step 2: Apply it in `CabinetView`'s empty state**

Change:

```swift
        if viewModel.isEmpty {
            ContentUnavailableView {
                Label("Your cabinet is empty", systemImage: "archivebox")
            } description: {
                Text("Add what's in your cabinet to get started")
            } actions: {
                Button("Add Ingredient") { isPresentingAddSheet = true }
                    .buttonStyle(.dsPrimary)
                    .frame(maxWidth: 280)
            }
        } else {
```

to:

```swift
        if viewModel.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("Your cabinet is empty")
                } icon: {
                    FloatingIcon(systemName: "archivebox")
                }
            } description: {
                Text("Add what's in your cabinet to get started")
            } actions: {
                Button("Add Ingredient") { isPresentingAddSheet = true }
                    .buttonStyle(.dsPrimary)
                    .frame(maxWidth: 280)
            }
        } else {
```

- [ ] **Step 3: Apply it in `FavouritesView`'s empty state**

Change:

```swift
                if viewModel.isEmpty {
                    ContentUnavailableView(
                        "No Favourites Yet",
                        systemImage: "heart",
                        description: Text("Recipes you love will appear here")
                    )
                } else {
```

to:

```swift
                if viewModel.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No Favourites Yet")
                        } icon: {
                            FloatingIcon(systemName: "heart")
                        }
                    } description: {
                        Text("Recipes you love will appear here")
                    }
                } else {
```

- [ ] **Step 4: Apply it in `RecipeResultsList`'s empty state**

Change:

```swift
        if grouped.isEmpty {
            ContentUnavailableView(
                "No Matching Recipes",
                systemImage: "wineglass",
                description: Text("Your cabinet didn't match any recipes. Try adding some base spirits like gin, rum, or vodka.")
            )
            .dsScreenBackground()
        } else {
```

to:

```swift
        if grouped.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Matching Recipes")
                } icon: {
                    FloatingIcon(systemName: "wineglass")
                }
            } description: {
                Text("Your cabinet didn't match any recipes. Try adding some base spirits like gin, rum, or vodka.")
            }
            .dsScreenBackground()
        } else {
```

- [ ] **Step 5: Build the app target**

Run: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add ios/NorseMixology/Components/FloatingIcon.swift ios/NorseMixology/Cabinet/CabinetView.swift ios/NorseMixology/Favourites/FavouritesView.swift ios/NorseMixology/Recipes/RecipeResultsList.swift
git commit -m "iOS: floating empty-state icons (Phase 12)"
```

---

## Task 6: Manual verification pass

No further code changes — run the app in the simulator against Phase 12's Verification checklist. Use the already-booted "iPhone 17 Pro" simulator (`mcp__Claude_Code_iOS_Simulator__control`, or Xcode directly).

- [ ] **Step 1: Perfect Match hero reveal**

Build a cabinet that produces at least one Perfect Match recipe. Open the Recipes tab fresh (fresh install or after clearing app data). Confirm: the Perfect Match badge shows a brief diagonal highlight sweep, the whole card pulses once right after, and neither replays on scrolling the card out of view and back.

- [ ] **Step 2: Staggered tier entrance**

With a cabinet producing results in all three tiers, confirm Perfect Match cards fade/slide in first, Almost There next, Worth Exploring last, with a light per-card stagger within each tier. Pull to refresh and confirm it replays. Switch to another tab and back without changing the cabinet — confirm it does **not** replay.

- [ ] **Step 3: Sequential flavour dots**

Open Cabinet or Add Ingredient and confirm the 5 flavour dots on a row fill in left-to-right on first appearance.

- [ ] **Step 4: Cabinet insertion**

Add a new ingredient end-to-end (search or browse → confirm → Add to Cabinet). Confirm no crash/glitch as the sheet dismisses over the newly-inserted row. Reopen Add Ingredient and search for the same ingredient — confirm its checkmark materializes with a small scale/fade rather than popping in, if the row re-renders from unchecked to checked without leaving the list (e.g. after adding a different ingredient while this search result stays mounted).

- [ ] **Step 5: Empty-state float**

Clear the cabinet and confirm its empty-state icon floats gently; confirm Favourites' and (with an unmatchable cabinet) Recipe Browser's empty states do too. Confirm CabinetView's "Add Ingredient" button and the title/description text stay still — only the icon moves.

- [ ] **Step 6: Reduce Motion pass**

Enable Reduce Motion (Simulator → Settings → Accessibility → Motion → Reduce Motion). Repeat Steps 1–5: confirm the hero sweep, card stagger, dot fill, cabinet insertion transition, and icon float are all gone or instant — nothing looks broken or half-applied (e.g. no icon stuck off-center, no badge stuck mid-sweep, no card stuck at 92% opacity).

- [ ] **Step 7: Performance**

Build a 150-result cabinet (or as close as the bundled catalog allows) and a 50-item cabinet (reuse Phase 6's stress scenarios). Confirm both scroll smoothly with these animations active — no visible frame drops.

- [ ] **Step 8: VoiceOver spot-check**

Enable VoiceOver. Confirm Recipe Browser cards are focusable and read correctly without waiting on the visual stagger, and that the empty-state icon's float doesn't produce extra or duplicate VoiceOver announcements (it should still read as a single combined label, same as before this phase).

- [ ] **Step 9: Update the Obsidian phase doc**

Edit `Phases/Phase 12 - iOS Motion & Delight Pass.md`'s Status line and check off every checklist/Verification item confirmed above, following the same pattern as Phases 6, 10, and 11. Record the deviations listed at the top of this plan (no literal chips, sweep instead of fill, closure-based `ContentUnavailableView`, low perceptibility of the cabinet-insertion animation) in its Notes section, the same way Phase 11 recorded its own build-time deviations.

- [ ] **Step 10: Merge**

Once verification is complete and the phase doc is updated, merge `phase-12-ios-motion-delight-pass` back to `main` (fast-forward, per this project's established branch-per-phase convention) and update `Overview.md`'s status line and Build Phases table row for Phase 12 to done.
