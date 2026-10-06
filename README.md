# Norse Mixology

A mixology app where you tell it what's in your cabinet and it finds the cocktails you can make — with smart substitution for what you're missing, computed entirely on-device.

## Platforms

| Platform | Location | Stack |
|---|---|---|
| iOS / iPadOS | [`ios/`](ios/) | Swift, SwiftUI, SwiftData, min iOS 17 |
| Android (**parked**) | [`android/`](android/) | Kotlin, Jetpack Compose, Room, min API 26 |

**Android is parked** until after the iOS launch ([#3](https://github.com/martinloesethjensen/norse-mixology/issues/3)). The code stays in the repo and still builds, but new features are iOS-only and aren't ported. The parity backlog is tracked in #3 and #2.

## Architecture

Fully local-first — no backend, no network calls in the MVP. The bundled ingredient taxonomy and recipe catalog (`taxonomy.json` / `recipes.json`) seed each platform's local database on first launch, and the recipe-matching/substitution engine runs entirely on-device. A Rust backend for sync and shared content updates is planned for a later release; see `NORSE_MIXOLOGY_BUILD.md` at the repo root for the full architecture reference.

## Local development

### iOS

Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd ios
xcodegen generate   # regenerates NorseMixology.xcodeproj from project.yml
open NorseMixology.xcodeproj
```

### Android

Requires Android Studio (or the `android` CLI) with SDK platform 26+.

```bash
cd android
./gradlew :app:assembleDebug
```

## Docs

`NORSE_MIXOLOGY_BUILD.md` is the living architecture reference this repo is built against. Full design rationale, the ingredient taxonomy, and per-phase build checklists live in the project's Obsidian vault.
