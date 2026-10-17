# Rune Identity — App Icon, Splash and Colours — Design

**Date:** 2026-10-17
**Status:** Draft, pending approval
**Scope:** iOS only (Android is parked, see #3). Replaces the "Modern Neon Bar" look with a new identity, "Rune".

---

## 1. Intent

The app is called Norse Mixology, but nothing about how it looks says Norse. The icon is a generic martini glass, and lime on near-black is a stock look shared with many other apps. The new identity gives the app one recognisable symbol and a palette that belongs to it.

**The idea:** the rune ᛉ (Algiz) already has the shape of a stemmed glass, with a stem and two arms opening upward. Drawn as a glass with a little liquid between its arms, it is both the rune and the drink. That mark is the icon, the splash, and the small brand mark in the app.

**Palette:** oxblood, brass and bone. Warm, dark and heavy, like an old hall: a different place from both the old neon bar and the cold Scandinavian-minimal look.

| Decision | Choice | Who |
|---|---|---|
| Direction | **Rune** (chosen over "Mead hall" horn and "Fjord" coupe) | Owner |
| Reach of the palette | **Whole app**, light and dark mode, as in the reviewed mockup | Owner |
| Fonts in the app | System fonts stay (SF Pro, existing `DSTextStyle`). Carved capitals (Cinzel) appear only in the splash wordmark | My call |
| Accent per mode | **Brass in dark, oxblood in light**, as in the mockup | Owner (approved via mockup) |
| Match badges in light mode | Tinted fill + dark text (not solid fill), as in the mockup | Owner (approved via mockup) |

## 2. Goals, non-goals, anti-goals

**Goals**
- A new app icon (default, dark, tinted variants) built on the ᛉ glass.
- A launch screen showing the ᛉ glass and wordmark, using iOS's built-in launch screen (no storyboard, no animation).
- A full replacement of the colour tokens in `Theme/DesignTokens.swift` and the `AccentColor` asset, in both appearances.
- `NORSE_MIXOLOGY_BUILD.md` → Design System section updated to describe "Rune".

**Non-goals**
- No layout, spacing, typography-scale or component-structure changes beyond what the badge style in §5.3 needs.
- No Android work. The Android launcher icon and theme stay as they are. Add a line to the parity backlog (#3) that Android needs the Rune identity.
- No animated or custom-drawn splash.
- No in-app custom font.

**Anti-goals (it fails if…)**
- …it reads as a fantasy/game app: no runic text strings, no knotwork, no faux-stone textures, no Cinzel in body UI. One rune, used as a mark.
- …text or status icons lose contrast. Brass on bone and lime-style greens on light backgrounds are the obvious traps (see §5.4).
- …"can make / swap / missing" become harder to tell apart. They must stay green / amber / grey, and stay distinct from the brass accent.

## 3. The mark

Geometry (in a 120×120 artboard; scale proportionally):

- Stem: vertical line x=60, from y=30 to y=92.
- Arms: from the fork (60,62) up to (34,32) and (86,32).
- Stroke: 6 units, square caps, mitred joins. Hard and carved, not rounded.
- Liquid: a filled triangle (40,42)–(80,42)–(60,62) sitting between the arms, under the strokes.
- Optical centring: the mark sits slightly high (the base of the stem is the visual anchor). Builder may nudge the vertical position so it looks centred.

Reference rendering: the "C · Rune" mockup in [`2026-10-17-rune-identity-mockups.html`](2026-10-17-rune-identity-mockups.html), which also has the approved light/dark recipe-list mockup. Where the mockup and the token tables differ, the tables win (they include fixes made after review). The source artwork is committed as SVG (see §6) so every PNG is regenerated from one file.

Small-size use in the app (e.g. next to a title): stroke-only, no liquid, in the accent colour. Whether and where the in-app mark appears is left to the builder. It is optional and must not add a new layout element to more than one screen.

## 4. Icon and splash

### 4.1 App icon (`AppIcon.appiconset`, existing three-file setup)

| Variant | Background | Mark | Liquid |
|---|---|---|---|
| Default (`icon-light.png`) | Oxblood `#4A1D22`, full bleed | Brass `#D2AE6A` | Deep red `#8E3A3F` |
| Dark (`icon-dark.png`) | Per Apple's dark-icon guidance (transparent or near-black; builder checks current HIG) | Brass `#D2AE6A` | `#8E3A3F` |
| Tinted (`icon-tinted.png`) | Per Apple's tinted-icon guidance | Grayscale rune; liquid as a lighter grey so it survives tinting | — |

1024×1024, no pre-rounded corners. Keep the existing `Contents.json` structure. Icon Composer / layered `.icon` format is **not** required (min iOS is 17). Builder may add it later.

### 4.2 Launch screen

Uses the `UILaunchScreen` Info.plist dictionary (replacing `INFOPLIST_KEY_UILaunchScreen_Generation`) via `project.yml`:

- `UIColorName`: a new colour asset `LaunchBackground` = the app's **Background** token for each appearance (`#2A1215` dark, `#F6EEE1` light), so there's no colour flash when the first screen appears. *(My call: the mockup splash was `#4A1D22`. Matching Background avoids the flash; the icon carries the brighter oxblood.)*
- `UIImageName`: a new image asset `LaunchMark`, the ᛉ glass with "Norse Mixology" beneath it in Cinzel SemiBold, rasterised (Cinzel is OFL, so baking it into an image is fine). Light variant: oxblood mark and wordmark. Dark variant: brass. Provide @2x/@3x or a PDF/SVG with "Preserve Vector Data".
- `UIImageRespectsSafeAreaInsets`: true.

## 5. Colours

### 5.1 Core tokens

Starting values. The builder may adjust a value only to meet the contrast floor in §5.4, and should record the change in the build reference.

| Token | Dark | Light |
|---|---|---|
| `background` | `#2A1215` | `#F6EEE1` |
| `surface` | `#3B1A1E` | `#FFFBF4` |
| `surfaceRaised` | `#4A2328` | `#EFE4D3` |
| `border` | `#5A2E33` | `#E2D4BE` |
| `textPrimary` | `#F0E4D0` | `#2A1215` |
| `textSecondary` | `#B9A99A` | `#7A6658` |
| `accent` | `#D2AE6A` (brass) | `#4A1D22` (oxblood) |
| `onAccent` (new; text on accent fills such as `DSPrimaryButtonStyle`) | `#3A2A0C` | `#F0E4D0` |

`accent` becomes **adaptive** (today it's one colour for both modes). Everywhere it's used as a foreground (stars, hearts, checkmarks, selection borders, `.tint`), oxblood is what shows in light mode. That's intended.

`AccentColor.colorset` gets the same light/dark pair so system controls match.

### 5.2 Match / availability colours

Exact and accent used to be the same lime. Now they're separate: green means "you can make this", brass means "brand / interactive".

| Token | Dark | Light | Used for |
|---|---|---|---|
| `matchExact` | `#7DB37A` | `#3F7A3C` | Icons and foreground text |
| `matchSubstituted` | `#E5803A` | `#A04E12` | Icons, foreground, tinted borders |
| `matchUnavailable` | `#7E6A62` | `#8A7B6E` | Greyed status |
| `matchExactBadgeFill` (new) | `#7DB37A` | `#DCEBD8` | Badge background |
| `matchExactBadgeText` (new) | `#14290F` | `#2D5A2A` | Badge label |
| `matchSubstitutedBadgeFill` (new) | `#E5803A` | `#F6DCC6` | Badge background |
| `matchSubstitutedBadgeText` (new) | `#3A1A06` | `#7A3A0C` | Badge label |

*(My call: "swap" moved from the mockup's amber `#E39A3B` to copper-orange, because in dark mode amber sat too close to the brass accent and they appear side by side on recipe cards. Brass ≈ 39° hue, copper ≈ 25°.)*

### 5.3 Badge style change

`MatchBadgeView` today fills with the match colour and labels with `onBadge` in both modes. It switches to the per-state fill/text pairs above: in dark mode that still looks solid; in light mode it becomes a tinted pill with dark text. In light mode the pill also gets a 1pt hairline border in its own text colour at ~35% opacity: recipe cards are `surfaceRaised`, and a pale tinted fill alone disappears against it (*my call*). `onBadge` is removed once nothing uses it.

The one-time "Perfect Match" highlight sweep in `MatchBadgeView` (white at 0.55 opacity) stays in dark mode; in light mode the builder picks a sweep colour that is visible on the pale fill. The effect itself is unchanged. Any other place that fills with a match colour and puts `onBadge` text on it follows the same pattern.

### 5.4 Flavour notes (Tasting Dots)

| Token | Dark | Light |
|---|---|---|
| `noteStrongText` | `#D2AE6A` | `#4A1D22` |
| `noteStrongFill` | `#4A2328` | `#F1E2CF` |
| `noteStrongBorder` | `#8C6E3A` | `#8E3A3F` |
| `noteMildBorder` | `#7E6A62` | `#9C8A7C` |
| `noteBar` | `#D2AE6A` | `#4A1D22` |

*(My call: the notes follow the accent, brass/oxblood, instead of green, so green keeps meaning "can make".)*

### 5.5 Contrast floor

Every text/background pair meets WCAG AA (4.5:1 body, 3:1 for ≥18pt or bold ≥14pt). Every meaningful icon meets 3:1 against the surface it sits on, including the grey "missing" `xmark` icon. Decorative outlines (the `border` token on cards, pills and dividers) are exempt, as they are today. Check in both appearances, including text on `surfaceRaised` and badges on `surface`. If a starting value fails, adjust that value, not the pairing.

### 5.6 Hard-coded colours

Leave `TakePhotoViewer`'s black backdrop and white spinner alone: a photo viewer stays black in both modes. No other hard-coded colours exist. Keep it that way (all colour from `DesignTokens`).

## 6. Assets and source

- Commit the master SVGs (icon variants, launch mark light/dark) under `ios/design/` (my call on location).
- Add a small script (e.g. `ios/scripts/render-icons.sh`) that renders the PNGs from the SVGs with a tool available via Homebrew (e.g. `rsvg-convert` or `resvg`), so the artwork can be regenerated. Text in the launch-mark SVG is converted to outlines so rendering doesn't depend on Cinzel being installed.

## 7. Done means

- Icon, dark icon, tinted icon look right on the Home Screen in a simulator (iOS 17 and the current iOS).
- Launch screen shows the mark on the matching background in both appearances, with no visible colour jump into the first screen.
- Every screen reviewed in light and dark with screenshots. No lime left anywhere (grep for `8FE388`).
- Contrast pairs from §5.5 checked (a short table in the PR description is enough).
- Existing unit/UI tests pass. `NORSE_MIXOLOGY_BUILD.md` Design System section rewritten for "Rune". Line added to #3.

## 8. Left to the builder

- Exact pixel nudges to the mark for optical balance, and the tinted-icon grey levels.
- Whether the small stroke-only mark appears in the app, and where (at most one screen).
- Rendering tool and script details.
- Adjusting any hex value to pass §5.5, with the change noted.
