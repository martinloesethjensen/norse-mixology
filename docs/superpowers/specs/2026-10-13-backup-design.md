# Backup File — Export and Restore — Design

**Date:** 2026-10-13
**Status:** Approved design, pending implementation plan
**Scope:** iOS only. Roadmap item **E**, first part: a backup file the user controls. iCloud sync (SwiftData + CloudKit) is a later, separate sub-project.

---

## 1. Goal and decisions

Since roadmap item C, the app holds data that cannot be rebuilt from the catalog: ratings, notes and photos, as well as the cabinet, favourites and shopping list. This design lets the user save all of it as one file, keep that file wherever they like, and restore from it, on the same phone or a new one. As with C, it is designed failure-first: a restore never deletes anything, never half-applies, and refuses bad files before it touches the store.

| Decision | Choice | Why |
|---|---|---|
| What E delivers now | **Export/import file** | Needs no Apple Developer account or iCloud container, and no model migration. Sync can follow later |
| Restore semantics | **Merge: the backup fills gaps; nothing on the phone is deleted** | Safe to restore the wrong file, or the same file twice |
| File format | **One AppleArchive file `.nmbackup`**: `manifest.json` plus a `photos/` folder | Photos stay real files (low memory, true size); iOS has no public unzip API, and AppleArchive is built in (iOS 14+, macOS 11+) |
| Device backup | The SwiftData store stays included in iCloud/Finder device backups (verified by a test) | That is the "lost my phone" path; the file is the "copy I control / moving phones" path |

Rejected: a single JSON file with base64 photos (photos grow by a third, and the whole file must be decoded in memory); a folder package (AirDrop, mail and some cloud apps flatten or reject packages); replace-on-restore (a wrong file destroys current data).

---

## 2. Format (schema version 2)

Archive contents:

```
manifest.json
photos/<photoId>.jpg          full image (≤ 1600 px, as stored)
photos/<photoId>-thumb.jpg    thumbnail (~320 px, as stored)
```

`manifest.json` (`BackupManifest`, `Codable`, ISO-8601 dates):

- `formatVersion: Int` (2), `appVersion: String`, `createdAt: Date`
  - Version 2 (2026-10-22) allows half-star ratings (`rating` 0…5 in steps of 0.5). Version 1 files, with whole-star ratings, still restore; the committed `backup-v1.nmbackup` fixture keeps that true.
- `cabinet: [CabinetRecord]`: every `CabinetItem` field, including `id`, the ids, names, brand, the ten flavour values and `dateAdded`
- `favourites: [FavouriteRecord]`: `id`, `recipeId`, `recipeName`, `dateFavourited`
- `shopping: [ShoppingRecord]`: `id`, `ingredientStyleId`, `styleName`, `dateAdded`
- `takes: [TakeRecord]`: `id`, `recipeId`, `recipeName`, `rating`, `notes`, `updatedAt`
- `photos: [PhotoRecord]`: `id`, `recipeId`, `dateAdded`, `fullFile`, `thumbnailFile` (archive-relative paths)

Ids are kept as they are, so a restore can recognise what it already has. Unknown JSON keys are ignored, so a version-1 reader tolerates additive fields.

---

## 3. Core (`NorseMixologyCore`)

- **`BackupWriter`**
  - `write(context:to directory:) throws -> URL` reads the store and writes `manifest.json` and the photo files into a temporary folder.
  - Photos are copied one at a time; each record's `full` data is read only while it is written.
  - It then packs the folder with AppleArchive into `Norse Mixology Backup YYYY-MM-DD.nmbackup` in the temporary directory and returns that URL.
  - The temporary folder is always removed, including on throw.
- **`BackupReader`**
  - `open(_ url:) throws -> OpenedBackup` unpacks into a temporary folder and decodes the manifest. `OpenedBackup` holds the manifest, the folder URL and a summary of counts.
  - It validates before returning:
    - the file is an archive
    - `formatVersion ≤ 2`
    - the manifest decodes
    - every referenced photo file exists and is non-empty
    - paths contain no `..` and no absolute paths (no path traversal)
    - ratings are 0…5
    - notes are ≤ 2,000 characters (longer notes are trimmed, as the app does)
  - It throws `BackupError.notABackup`, `.newerVersion`, `.damaged` or `.outOfSpace`.
  - `OpenedBackup.close()` removes the folder.
- **`BackupMerger`**
  - `merge(_ backup: OpenedBackup, into context:) throws -> RestoreResult`. All changes go in one context, with one `save()`. If the save fails, it calls `rollback()` and throws `BackupError.restoreFailed`, so nothing is changed.
  - **Cabinet:** a record is added unless the phone already has an item with the same `ingredientStyleId`.
  - **Shopping list:** a record is added unless the same `ingredientStyleId` is already there, or the cabinet (after the merge) contains that style.
  - **Favourites:** a record is added unless the same `recipeId` is already there.
  - **Takes, with no take on the phone:** the take is added.
  - **Takes, with both present:** the take with the newer `updatedAt` supplies `rating` and `notes`.
  - **Photos:** a photo is skipped if the phone already has the same id. New photos are added oldest first until the recipe has `TakeLimits.maxPhotos`; the rest count as `photosSkippedForLimit`. A take is created for photos whose recipe has no take.
  - **Recipes no longer in the catalog** are restored as normal.
  - `RestoreResult` has per-kind added counts, `takesUpdated` and `photosSkippedForLimit`. `isEmpty` is true when nothing changed ("Already up to date").
- **`BackupError: Error, Equatable`** has the cases `notABackup`, `newerVersion`, `damaged`, `outOfSpace` and `restoreFailed`.
- The view model **`BackupViewModel`** (`@MainActor @Observable`, app root) wraps these:
  - **State:** `state: idle | preparing | ready(URL) | opened(summary) | restoring | finished(RestoreResult) | failed(BackupError)`.
  - **Methods:** `makeBackup()`, `open(url:)`, `confirmRestore()`, `cancel()`.
  - **Off the main actor:** writing, packing, unpacking and validation. Only the store reads and the merge run on the main context.
  - **Refresh:** after a restore it refreshes the Cabinet, Favourites, Shopping and Take view models.
- **Stale temporary folders:** on launch, `BackupWriter.cleanUpStaleTemporaryFiles()` removes leftover `NorseMixologyBackup-*` folders and archives in the temporary directory.

---

## 4. App (`ios/NorseMixology`)

- **Settings → "Backup" section**
  - **Back up now.** While building, the row shows "Preparing backup…" with a progress view. Then a `ShareLink`/share sheet opens with the `.nmbackup` file (Save to Files, AirDrop and so on).
  - **Restore from backup…** opens `fileImporter` filtered to the backup type. A summary sheet then appears:
    - "Backup from 13 Oct 2026" with counts per kind
    - the line "Nothing on this phone will be deleted."
    - **Restore** and **Cancel** buttons
    - the result after restoring: "Added 3 cabinet items, 2 ratings, 7 photos; 2 photos skipped (6-photo limit)", or "Already up to date"
  - **Footnote:** "Your iPhone's own iCloud backup also includes this app's data. Use this to keep a copy you control or to move to a new phone."
- **Document type:** an exported UTType `dev.martinloeseth.norsemixology.backup` (conforms to `public.data`, extension `nmbackup`), declared in `project.yml` Info.plist (`UTExportedTypeDeclarations`, `CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace: false`). Opening a `.nmbackup` from Files or AirDrop arrives through `.onOpenURL` and goes straight to the restore summary.
- **Errors** appear as one alert with a whole-phrase message per `BackupError`:
  - `notABackup`: "This file isn't a Norse Mixology backup."
  - `newerVersion`: "This backup was made by a newer version of the app. Update the app to restore it."
  - `damaged`: "This backup is damaged and can't be restored."
  - `outOfSpace`: "There isn't enough free space. Free some space and try again."
  - `restoreFailed`: "Couldn't restore. Nothing was changed."
- **Conventions:** design tokens only, 44 pt targets, VoiceOver labels, structured logging (`AppLog`, which never logs note contents), strings in `Localizable.xcstrings`.

---

## 5. Failure modes

| Failure | Behaviour | Test |
|---|---|---|
| Not an archive, empty file, or wrong archive | `notABackup`; store untouched | Reader test with random bytes, an empty file, an archive without a manifest |
| Newer `formatVersion` | `newerVersion`; store untouched | Reader test with `formatVersion` one above the current |
| Manifest references a missing or empty photo | `damaged`; store untouched | Reader test |
| Path traversal in a manifest path (`../`, absolute) | `damaged` | Reader test |
| Out-of-range rating, or notes over the limit | Rating → `damaged`; notes trimmed | Reader test |
| Disk full while writing or unpacking | `outOfSpace`; temporary files removed | Writer/reader error-mapping test (simulated), manual |
| Save fails during the merge | `rollback()`, `restoreFailed`, nothing changed | Merger test with an injected save failure |
| The same file restored twice | Second result `isEmpty` ("Already up to date") | Merger test |
| Newer take on the phone | Phone's rating and notes kept; backup photos still combined | Merger test |
| Photos over the limit | Added oldest first up to 6; rest counted as skipped | Merger test |
| Take for a recipe no longer in the catalog | Restored | Merger test |
| Large backup (many photos) | Written and read one photo at a time; no full-library data in memory | Writer test with ~100 photos, memory sanity check |
| App killed mid-backup | Stale temporary folders removed at next launch | Clean-up test |
| Store excluded from device backup | Must not happen | Test asserts the store URL lacks `isExcludedFromBackup` |
| Empty app | Produces a valid file with zero items; restoring it changes nothing | Round-trip test |

---

## 6. Testing

- **Core:**
  - `BackupRoundTripTests`: populate an in-memory store, write, open, merge into an empty store, and check the data is identical (including photo bytes).
  - `BackupReaderTests`: every refusal in §5.
  - `BackupMergerTests`: the rules, idempotence, the limit, rollback on save failure.
  - `BackupViewModelTests`: state transitions.
  - Writer clean-up test.
- **Simulator (controller):**
  - Back up and save to Files.
  - Delete a rating, restore, and check the summary, result and data.
  - Restore the same file again ("Already up to date").
  - Tap the file in Files to open the app at the summary.
  - Try a non-backup file.

---

## 7. Out of scope

Automatic or scheduled backups, encryption or a password on the file, iCloud sync (next sub-project of E), choosing which parts to restore, replace-on-restore, backing up the taste profile or settings (they live in `UserDefaults`; revisit with sync), and Android.
