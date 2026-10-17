# Rune Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Modern Neon Bar" look with the "Rune" identity: a new app icon, a new launch screen, and a new colour palette across the whole iOS app in both appearances.

**Architecture:** The palette's hex values move into a pure, UIKit-free table in `NorseMixologyCore` (`RunePalette`) so contrast, hue separation and asset-catalog agreement are unit-tested with `swift test`. The app's `DesignTokens` reads from that table; screens keep reading `DesignTokens` and don't change, except `MatchBadgeView` (new badge fill/text pairs). Icon and launch artwork are SVG masters rendered to PNG by a script. The launch screen moves from generated to a `UILaunchScreen` dictionary.

**Tech Stack:** Swift / SwiftUI, XCTest in the SPM core package, xcodegen `project.yml` plus the hand-maintained `project.pbxproj`, `rsvg-convert` (installed at `/opt/homebrew/bin/rsvg-convert`).

**Spec:** `docs/superpowers/specs/2026-10-17-rune-identity-design.md`. The reference mockups are in `docs/superpowers/specs/2026-10-17-rune-identity-mockups.html`. Where the spec's tables and the mockups differ, the tables win.

## Global Constraints

- iOS only. No changes under `android/`.
- Min iOS 17.0 (unchanged). Keep the three-PNG `AppIcon.appiconset`; no Icon Composer `.icon`.
- Every colour comes from `DesignTokens`; the only hard-coded colours allowed are `TakePhotoViewer`'s black backdrop and white spinner.
- System fonts in the app (existing `DSTextStyle`). Cinzel appears only, outlined, in the launch-mark artwork.
- No runic text strings, knotwork or textures anywhere (spec §2 anti-goals).
- The hex values in spec §5.1–5.4 are starting values. Change one only to pass the contrast floor (§5.5), and record the change in `NORSE_MIXOLOGY_BUILD.md`.
- Contrast floor: text ≥ 4.5:1 (≥ 3:1 for large/bold-large), meaningful icons (including the "missing" `xmark`) ≥ 3:1. The `border` token is decorative and exempt.
- `project.pbxproj` is hand-maintained (see `NORSE_MIXOLOGY_BUILD.md`). Any new file or build-setting change must go into **both** `ios/project.yml` and `ios/NorseMixology.xcodeproj/project.pbxproj`. Do not run `xcodegen generate` to sync them.
- Core tests: `cd ios/Packages/NorseMixologyCore && swift test`. App build: `cd ios && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,id=<booted simulator id>' build`. Get the id from `xcrun simctl list devices available`, and always pass it by id, never by name.

## Review Focus

1. **Swap vs accent in dark mode:** copper "swap" and brass accent sit next to each other on recipe cards and must read as different colours. Pinned by `testSwapAndAccentHuesAreApartInDark` (Task 1).
2. **Light-mode badges on `surfaceRaised` cards:** the tinted fill nearly vanishes, so the hairline and the text carry the badge. Pinned by `testBadgeTextContrast` (Task 1). The hairline gets checked in Task 2's screenshot step.
3. **"Missing" icon in light mode:** `matchUnavailable` on `surface` and `surfaceRaised` must stay ≥ 3:1. Pinned by `testStatusIconContrast` (Task 1).
4. **Colour flash on launch:** `LaunchBackground` must equal the `background` token in each appearance, and `AccentColor` must equal `accent`. Pinned by `testAssetCatalogColoursMatchPalette` (Tasks 2 and 4).
5. **Lime left behind:** no `8FE388`, and no "lime" in comments, anywhere under `ios/NorseMixology` outside the bundled JSON (where "lime" is the fruit). Pinned by `testNoNeonLimeLeft` (Task 2).

---

## File structure

| File | Responsibility |
|---|---|
| `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RunePalette.swift` (create) | Hex table for every token (dark/light pairs) and the WCAG contrast and hue helpers |
| `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RunePaletteTests.swift` (create) | Contrast, hue separation, asset-catalog agreement, no-lime |
| `ios/NorseMixology/Theme/DesignTokens.swift` (modify) | Maps `RunePalette` to SwiftUI `Color`, adds `onAccent` and the badge tokens, removes `onBadge` |
| `ios/NorseMixology/Recipes/MatchBadgeView.swift` (modify) | Per-state fill/text, light-mode hairline, light-mode sweep colour |
| `ios/NorseMixology/Assets.xcassets/AccentColor.colorset/Contents.json` (modify) | Light/dark accent |
| `ios/design/*.svg` (create) | Master artwork |
| `ios/scripts/render-icons.sh` (create) | Renders the icon and launch-mark PNGs from the masters |
| `ios/NorseMixology/Assets.xcassets/AppIcon.appiconset/*.png` (replace) | Rendered icons |
| `ios/NorseMixology/Assets.xcassets/LaunchBackground.colorset/` and `LaunchMark.imageset/` (create) | Launch screen assets |
| `ios/NorseMixology/Info.plist` (create) | The `UILaunchScreen` dict only; merged with the generated Info.plist |
| `ios/project.yml`, `ios/NorseMixology.xcodeproj/project.pbxproj` (modify) | `INFOPLIST_FILE`; remove `UILaunchScreen_Generation` |
| `NORSE_MIXOLOGY_BUILD.md` (modify) | Design System section rewritten for "Rune" |

---

### Task 1: `RunePalette` in the core package, with contrast tests

**Files:**
- Create: `ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Models/RunePalette.swift`
- Create: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RunePaletteTests.swift`

**Interfaces:**
- Produces:
  - `public struct PaletteColor: Equatable, Sendable { public let dark: UInt32; public let light: UInt32 }` with `init(dark:light:)` and `init(_ both: UInt32)` for mode-independent colours.
  - `public enum RunePalette` with one `public static let` per token, named exactly: `background, surface, surfaceRaised, border, textPrimary, textSecondary, accent, onAccent, matchExact, matchSubstituted, matchUnavailable, matchExactBadgeFill, matchExactBadgeText, matchSubstitutedBadgeFill, matchSubstitutedBadgeText, noteStrongText, noteStrongFill, noteStrongBorder, noteMildBorder, noteBar`, plus the icon-only constants `iconOxblood = 0x4A1D22`, `iconBrass = 0xD2AE6A`, `iconLiquid = 0x8E3A3F` (plain `UInt32`).
  - `public enum WCAG { public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double; public static func hueDegrees(_ c: UInt32) -> Double }`.

Values: exactly the spec §5.1, §5.2 and §5.4 tables (dark first, light second).

- [ ] **Step 1: Write the failing tests** in `RunePaletteTests.swift` (XCTest, `@testable import NorseMixologyCore`, matching the other test files):

```swift
func testContrastRatioMatchesWCAGReference() {
    XCTAssertEqual(WCAG.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
    XCTAssertEqual(WCAG.contrastRatio(0x777777, 0xFFFFFF), 4.48, accuracy: 0.01)
}

func testTextContrast() {
    // (foreground, backgrounds) — every pair ≥ 4.5 in both modes
    let pairs: [(PaletteColor, [PaletteColor])] = [
        (RunePalette.textPrimary,   [RunePalette.background, RunePalette.surface, RunePalette.surfaceRaised]),
        (RunePalette.textSecondary, [RunePalette.background, RunePalette.surface, RunePalette.surfaceRaised]),
        (RunePalette.onAccent,      [RunePalette.accent]),
        (RunePalette.noteStrongText,[RunePalette.noteStrongFill]),
    ]
    // assert for .dark and .light separately, message names the pair and the mode
}

func testBadgeTextContrast() {
    // matchExactBadgeText on matchExactBadgeFill, matchSubstitutedBadgeText on
    // matchSubstitutedBadgeFill: ≥ 4.5 in both modes
}

func testStatusIconContrast() {
    // accent, matchExact, matchSubstituted, matchUnavailable, noteBar
    // against surface and surfaceRaised: ≥ 3.0 in both modes
}

func testSwapAndAccentHuesAreApartInDark() {
    let d = abs(WCAG.hueDegrees(RunePalette.accent.dark) - WCAG.hueDegrees(RunePalette.matchSubstituted.dark))
    XCTAssertGreaterThanOrEqual(d, 10)
}
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RunePaletteTests`
Expected: compile failure, `cannot find 'WCAG' in scope`.

- [ ] **Step 3: Implement `RunePalette.swift`**

`contrastRatio` uses WCAG 2.x relative luminance (sRGB channel `c/12.92` if `c ≤ 0.03928`, else `((c+0.055)/1.055)^2.4`; weights 0.2126/0.7152/0.0722; ratio `(L1+0.05)/(L2+0.05)` with L1 the lighter). `hueDegrees` is the standard HSL hue in 0..<360.

- [ ] **Step 4: Run the tests and check they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RunePaletteTests`
Expected: PASS. If a contrast test fails, adjust **that token's hex** per the Global Constraints (not the test), and note the change for Task 5.

Two spec starting values are already known to fail and must change: light `textSecondary` `#7A6658` on `surfaceRaised` is 4.32:1, so use `#705C4F` (5.0:1). Dark `matchUnavailable` `#7E6A62` on `surfaceRaised` is 2.64:1, so use `#8C7870` (≥ 3:1 on both surfaces). Use the same new value for dark `noteMildBorder`, which today shares the old one.

- [ ] **Step 5: Run the full core suite**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/NorseMixologyCore
git commit -m "core: RunePalette tokens with contrast tests"
```

---

### Task 2: Wire the palette into the app (tokens, accent asset, badges)

**Files:**
- Modify: `ios/NorseMixology/Theme/DesignTokens.swift`
- Modify: `ios/NorseMixology/Recipes/MatchBadgeView.swift`
- Modify: `ios/NorseMixology/Assets.xcassets/AccentColor.colorset/Contents.json`
- Modify: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RunePaletteTests.swift`

**Interfaces:**
- Consumes: `RunePalette`, `PaletteColor` (Task 1).
- Produces: `Color.adaptive(_ c: PaletteColor) -> Color`; `DesignTokens.onAccent`, `.matchExactBadgeFill`, `.matchExactBadgeText`, `.matchSubstitutedBadgeFill`, `.matchSubstitutedBadgeText`; `MatchBadgeState.badgeFill: Color` and `.badgeText: Color` (in `DesignTokens.swift`, next to the existing `color`). `DesignTokens.onBadge` is removed.

- [ ] **Step 1: Write the failing tests** in `RunePaletteTests.swift`

```swift
func testAssetCatalogColoursMatchPalette() throws {
    // Locate ios/NorseMixology/Assets.xcassets from #filePath, as AppBundleCatalogTests does.
    // Parse AccentColor.colorset/Contents.json: the entry with appearance luminosity=dark
    // equals RunePalette.accent.dark; the entry without appearances equals .light.
    // (Task 4 adds the same assertion for LaunchBackground.colorset vs RunePalette.background.)
}

func testNoNeonLimeLeft() throws {
    // Enumerate *.swift and *.json files under ios/NorseMixology, skipping Resources/.
    // None contains "8FE388" (case-insensitive) or "0x8F, 0xE3" components; no .swift file contains "lime".
}
```

- [ ] **Step 2: Run the tests and check they fail**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RunePaletteTests`
Expected: both new tests FAIL (the accent asset is still lime; `DesignTokens.swift` still mentions lime).

- [ ] **Step 3: Implement**
  - `DesignTokens`: every token reads `Color.adaptive(RunePalette.<same name>)`. Delete `onBadge` and any doc comment that says lime/gold/neon; update the type doc comment to "Rune" tokens. `DSPrimaryButtonStyle` uses `onAccent`. `AvailabilityStatus.color` and `MatchBadgeState.color` are unchanged in shape.
  - `AccentColor.colorset`: a universal entry (light `#4A1D22`) plus a `luminosity: dark` entry (`#D2AE6A`).
  - `MatchBadgeView`: text `state.badgeText`, fill `state.badgeFill`. In light mode (`@Environment(\.colorScheme)`), add `.overlay(Capsule().strokeBorder(state.badgeText.opacity(0.35), lineWidth: 1))`. The sweep's highlight colour is `.white.opacity(0.55)` in dark and `state.badgeText.opacity(0.25)` in light. Update the type's doc comment (green = everything on hand, copper = substitutions).
  - Anything else that pairs a match colour fill with dark text follows the badge pattern (spec §5.3). `grep -rn "onBadge" ios/NorseMixology` must return nothing.

- [ ] **Step 4: Run the tests and check they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RunePaletteTests`
Expected: PASS.

- [ ] **Step 5: Build the app**

Run: the app build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Screenshot review**

Install and launch in the simulator. For both appearances (`xcrun simctl ui <id> appearance dark|light`), screenshot: Cabinet, Shopping list, Recipes (with at least one "can make" and one "swap" card), Recipe detail (ingredients, flavour notes, stars/heart), filter sheet, Favourites, taste onboarding. Check them against the mockup file. Badge hairlines show on light cards, nothing is lime, and swap and brass look different. Save the screenshots in the scratchpad for the PR.

- [ ] **Step 7: Commit**

```bash
git add ios/NorseMixology ios/Packages/NorseMixologyCore/Tests
git commit -m "iOS: apply Rune palette to every screen"
```

---

### Task 3: App icon artwork and render script

**Files:**
- Create: `ios/design/rune-mark.svg`, `ios/design/icon-light.svg`, `ios/design/icon-dark.svg`, `ios/design/icon-tinted.svg`
- Create: `ios/scripts/render-icons.sh`
- Replace: `ios/NorseMixology/Assets.xcassets/AppIcon.appiconset/icon-light.png`, `icon-dark.png`, `icon-tinted.png` (the `Contents.json` stays as is)

**Interfaces:**
- Consumes: `RunePalette.iconOxblood`, `.iconBrass`, `.iconLiquid` (Task 1). The SVGs use the same hex values.
- Produces: `ios/scripts/render-icons.sh` (no arguments, run from anywhere) renders every `ios/design/*.svg` that has a target in its table to the right asset path. Task 4 adds the launch-mark rows.

- [ ] **Step 1: Draw `rune-mark.svg`** using the spec §3 geometry (120 artboard; stem x=60 y30→92; arms from (60,62) to (34,32) and (86,32); stroke 6, square caps, miter joins; liquid triangle (40,42)(80,42)(60,62) under the strokes).
- [ ] **Step 2: Build the three icon SVGs** at 1024×1024, with no rounded corners, following the spec §4.1 table. Scale the mark so the rune's bounding box is about 58% of the canvas height, and nudge it for optical centre. Dark and tinted backgrounds follow Apple's current HIG for those variants. The tinted variant is grayscale, and its liquid is a lighter grey than the strokes.
- [ ] **Step 3: Write `render-icons.sh`** (`set -euo pipefail`, `rsvg-convert -w 1024 -h 1024`). Fail with a clear message if `rsvg-convert` is missing (`brew install librsvg`).
- [ ] **Step 4: Render and verify the files**

Run: `ios/scripts/render-icons.sh && sips -g pixelWidth -g pixelHeight -g hasAlpha ios/NorseMixology/Assets.xcassets/AppIcon.appiconset/icon-light.png`
Expected: 1024 × 1024, `hasAlpha: no` for the default icon.

- [ ] **Step 5: Check on the Home Screen.** Build, install, go to the Home Screen and screenshot in light, dark and tinted (Settings → Home Screen → Customize, on a simulator running iOS 18 or later). The rune reads clearly at small size, and the liquid still shows in the tinted icon.
- [ ] **Step 6: Commit**

```bash
git add ios/design ios/scripts/render-icons.sh ios/NorseMixology/Assets.xcassets/AppIcon.appiconset
git commit -m "iOS: Rune app icon"
```

---

### Task 4: Launch screen

**Files:**
- Create: `ios/design/launch-mark-light.svg`, `ios/design/launch-mark-dark.svg`
- Create: `ios/NorseMixology/Assets.xcassets/LaunchBackground.colorset/Contents.json`
- Create: `ios/NorseMixology/Assets.xcassets/LaunchMark.imageset/` (`Contents.json` + light/dark @2x/@3x PNGs)
- Create: `ios/NorseMixology/Info.plist`
- Modify: `ios/scripts/render-icons.sh`, `ios/project.yml`, `ios/NorseMixology.xcodeproj/project.pbxproj` (both build configurations, currently lines ~437 and ~469)
- Modify: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/RunePaletteTests.swift`

**Interfaces:**
- Consumes: `RunePalette.background`, `render-icons.sh` (Task 3).

- [ ] **Step 1: Extend `testAssetCatalogColoursMatchPalette`.** `LaunchBackground.colorset` must equal `RunePalette.background` (light `#F6EEE1`, dark `#2A1215`).
- [ ] **Step 2: Run it and check it fails**

Run: `cd ios/Packages/NorseMixologyCore && swift test --filter RunePaletteTests/testAssetCatalogColoursMatchPalette`
Expected: FAIL, colorset not found.

- [ ] **Step 3: Create the `LaunchBackground` colorset** (universal = light, plus a `luminosity: dark` entry). Run the test again and check it passes.
- [ ] **Step 4: Draw the launch marks.** The mark goes above "Norse Mixology" in Cinzel SemiBold with the text **converted to outlines** (for example with fontTools and the OFL Cinzel TTF from the google/fonts repo; any tool is fine as long as the committed SVG has no `<text>`). Light version: oxblood `#4A1D22` mark and wordmark, liquid `#8E3A3F`. Dark version: brass `#D2AE6A`, liquid `#8E3A3F`. Transparent background. Size the 1x artwork about 120pt wide.
- [ ] **Step 5: Add `LaunchMark` rows to `render-icons.sh`** (@2x and @3x, light and dark). Render, then write `LaunchMark.imageset/Contents.json` with `luminosity: dark` entries.
- [ ] **Step 6: Switch the launch screen config**
  - `ios/NorseMixology/Info.plist`: a plist containing only `UILaunchScreen` → `UIColorName = LaunchBackground`, `UIImageName = LaunchMark`, `UIImageRespectsSafeAreaInsets = true`.
  - Both `project.yml` and every app-target configuration in `project.pbxproj`: add `INFOPLIST_FILE = NorseMixology/Info.plist`, and remove `INFOPLIST_KEY_UILaunchScreen_Generation`. Keep `GENERATE_INFOPLIST_FILE = YES` so the other keys still merge in. In `project.yml`, exclude `Info.plist` from `sources` resources. In `pbxproj`, don't add it to the Resources build phase.
- [ ] **Step 7: Build and verify the merged plist**

Run: the app build command, then `plutil -p <built .app>/Info.plist | grep -A4 UILaunchScreen` and `plutil -p <built .app>/Info.plist | grep CFBundleDisplayName`
Expected: `** BUILD SUCCEEDED **`; `UILaunchScreen` shows the three keys; the display name is still "Norse Mixology".

- [ ] **Step 8: Check the launch on the simulator.** Delete the app first, since iOS caches launch screens. Install, then cold-launch in light and in dark and screen-record or screenshot the launch. The mark sits centred on the matching background, and there's no colour jump into the first screen.
- [ ] **Step 9: Commit**

```bash
git add ios/design ios/scripts ios/NorseMixology ios/project.yml ios/NorseMixology.xcodeproj/project.pbxproj ios/Packages/NorseMixologyCore/Tests
git commit -m "iOS: Rune launch screen"
```

---

### Task 5: Build reference and final sweep

**Files:**
- Modify: `NORSE_MIXOLOGY_BUILD.md` (section `## Design System — "Modern Neon Bar"`, around line 250)

- [ ] **Step 1: Rewrite the section** as `## Design System — "Rune"`. Include the token table (dark/light) from `RunePalette`, the match/badge table and the notes table. Add one line saying `RunePalette` (core) holds the values and `DesignTokens` maps them, with contrast pinned by `RunePaletteTests`. Note the icon/launch sources (`ios/design/`, `ios/scripts/render-icons.sh`). Record any hex value Task 1 or Task 2 had to change, with its reason.
- [ ] **Step 2: Run the full check**

Run: `cd ios/Packages/NorseMixologyCore && swift test 2>&1 | tail -3`, then the app build, then `grep -rni "8FE388\|neon" ios/NorseMixology --include=*.swift; grep -n "Neon" NORSE_MIXOLOGY_BUILD.md`
Expected: 0 failures; build succeeded; both greps empty.
- [ ] **Step 3: Draft the line for issue #3** (Android needs the Rune identity: icon, launch, palette from `RunePalette`). **Don't post it.** Give the text to the owner and let them decide whether to post it.
- [ ] **Step 4: Commit**

```bash
git add NORSE_MIXOLOGY_BUILD.md
git commit -m "docs: build reference for the Rune design system"
```

The PR description includes the screenshots from Tasks 2–4 and a short contrast table (pairs and ratios, printed from the test run).
