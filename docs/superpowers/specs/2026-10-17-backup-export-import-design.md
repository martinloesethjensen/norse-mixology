# Backup — Export and Import — Design

**Date:** 2026-10-17
**Status:** Approved 2026-10-17 (decisions in §7).
**Scope:** iOS only (Android parked, #3). Roadmap **E, part 1** (see `2026-10-04-recipe-catalog-browse-design.md` §7, revised by #6). It ships with **C** ("My take", `2026-10-06-recipe-take-design.md`), which is already on `main`. iCloud sync (E, part 2) follows custom recipes (D).

---

## 1. Goal and decisions

"My take" added the first data the app can't rebuild: ratings, notes and photos. Today none of it survives a lost phone, a fresh install, or moving to a new device. Let the user **export everything to one file** and **restore it later**, on this phone or another.

Guiding principle: **failure first.** A restore must never leave the store half-replaced, and a damaged or hostile file must never crash the app or touch the user's data.

| Decision | Choice | Why |
|---|---|---|
| What's in a backup | All user data: cabinet, favourites, shopping list, recipe takes, photos, taste profile, pantry staples | Everything the user created. The catalog isn't included, because it's public and versioned |
| Not included | `@SceneStorage` UI state, the catalog, caches | Rebuilt or re-downloaded automatically |
| Container | **One `.norsebackup` file: a ZIP** holding `manifest.json`, `data.json` and `photos/<id>.jpg` | One file to AirDrop, save in Files or email. Standard enough to inspect and to read from Android later. *(Decision 1)* |
| Photos | Only the **full** JPEG. Thumbnails are regenerated on import with `PhotoProcessor` | Halves photo storage in the file, and re-processing doubles as validation of untrusted image data |
| Restore | **Replace everything**, after a confirmation that shows what the backup contains | Predictable for the main use (new phone, reinstall). No merge rules to explain. *(Decision 2)* |
| Atomicity | Validate the whole file first, then replace inside one SwiftData save; preferences are written only after the save succeeds | A failure at any point leaves the current data untouched |
| Where | **Settings → Backup**: "Export backup", "Restore from backup", "Last exported" | One place. No new tab |

Rejected:
- **One JSON file with base64 photos:** a third bigger, and it has to be held in memory whole.
- **A directory package:** some share targets flatten or reject it.
- **Automatic backups:** they need a destination. That's iCloud, so it belongs to part 2.

---

## 2. File format (version 1)

```
Norse Mixology Backup 2026-10-17.norsebackup   (ZIP)
├── manifest.json
├── data.json
└── photos/
    └── <photo-uuid>.jpg                       (stored, not deflated: already JPEG)
```

**`manifest.json`** is read first. It's small and enough for the confirmation sheet.

```json
{
  "format": "dev.martinloeseth.norsemixology.backup",
  "formatVersion": 1,
  "createdAt": "2026-10-17T21:30:00Z",
  "appVersion": "1.0 (1)",
  "catalogContentVersion": "48c3086b",
  "counts": { "cabinetItems": 24, "favourites": 8, "shoppingItems": 3, "takes": 5, "photos": 12 }
}
```

**`data.json`** holds plain DTOs mirroring the SwiftData models field for field. They're decoupled from the `@Model` classes, so a schema change can keep reading version 1:

```json
{
  "cabinetItems":  [ { "id", "ingredientStyleId", "ingredientFamilyId", "categoryId", "displayName", "brand",
                       "style", "family", "category", "flavorProfile": { …10 values }, "dateAdded" } ],
  "favourites":    [ { "id", "recipeId", "recipeName", "dateFavourited" } ],
  "shoppingItems": [ { "id", "ingredientStyleId", "styleName", "dateAdded" } ],
  "takes":         [ { "id", "recipeId", "recipeName", "rating", "notes", "updatedAt" } ],
  "photos":        [ { "id", "recipeId", "dateAdded", "file": "photos/<id>.jpg" } ],
  "preferences":   { "tasteProfile": { …UserTasteProfile }, "pantryStaples": ["sugar", "lemonsAndLimes"] }
}
```

- Dates are ISO 8601 UTC. Unknown keys are ignored, so later versions can add fields.
- A higher `formatVersion` is refused ("made by a newer version of Norse Mixology").
- **Cabinet items are snapshots**, as they are in the store. A style that has since left the catalog restores as a ghost item, which the matcher already handles. Favourites and takes keep their cached `recipeName` for recipes no longer in the catalog.
- **Size:** a full photo is about 0.3 to 0.6 MB. A typical backup with a few dozen photos is a few MB to about 30 MB. The worst case (6 photos on every recipe) is about 0.5 GB, so export and import stream entries and never hold every photo in memory.

---

## 3. Core (`NorseMixologyCore`)

```swift
public struct BackupManifest: Codable, Equatable, Sendable { … }   // §2
public struct BackupData: Codable, Equatable, Sendable { … }       // §2 DTOs

public enum BackupExporter {
    /// Reads the store and preferences and writes a .norsebackup to `url`.
    /// Runs off the main actor with its own ModelContext.
    public static func export(container: ModelContainer, defaults: UserDefaults, catalogVersion: String?,
                              appVersion: String, to url: URL, now: Date) throws -> BackupManifest
}

public struct BackupContents: Sendable {          // validated, ready to restore
    public let manifest: BackupManifest
    public let data: BackupData
    public let photoFiles: [UUID: URL]            // extracted to a temporary directory
}

public enum BackupReader {
    public static func readManifest(_ url: URL) throws -> BackupManifest   // for the confirmation sheet
    public static func read(_ url: URL, into tempDirectory: URL) throws -> BackupContents
}

public enum BackupRestorer {
    /// Replaces all user data in one save. On any error the store and preferences are unchanged.
    public static func restore(_ contents: BackupContents, container: ModelContainer, defaults: UserDefaults) throws
}

public enum BackupError: Error, Equatable {
    case notABackup, newerFormat(Int), damaged(String), tooLarge, photoUnreadable(UUID), saveFailed
}
```

### Validation (in `BackupReader.read`, before anything is written)

- `format` must match and `formatVersion` must be ≤ 1. Both JSON files must decode, and the counts must match `data.json`.
- IDs are unique within each list, and every `photos[].file` exists in the archive.
- Values are checked against existing rules:
  - ratings must be in `TakeLimits.ratingRange`;
  - notes over `TakeLimits.maxNotesLength` are truncated, as typing would;
  - a recipe with more than `TakeLimits.maxPhotos` photos keeps the first 6 by `dateAdded`;
  - flavour values must be in 0…1.

  A take that is empty after this follows the existing "empty take doesn't exist" rule.
- Every photo goes through `PhotoProcessor.process`, which validates the image, caps it at 1600 px and builds the thumbnail. A photo that fails is a `photoUnreadable` error. One silently missing photo would be worse than a clear refusal.

### Untrusted-file guards

The file can come from anywhere (AirDrop, Mail):
- Only the three expected entry names are read, so there's no path traversal.
- Caps: 1 MB for `manifest.json`, 20 MB for `data.json`, 25 MB per photo, and 2 GB in total, all checked while streaming.
- Entries are extracted only into a fresh temporary directory, which is deleted afterwards.

### Restore

1. In one `ModelContext` with autosave off:
   - delete every `CabinetItem`, `FavouriteRecipe`, `ShoppingItem`, `RecipeTake` and `RecipePhoto`;
   - insert the backup's records, keeping their IDs;
   - `save()` once.
2. If the save throws, `rollback()` and return `saveFailed`. The store is unchanged.
3. Only after a successful save, write the taste profile and pantry staples.
4. The app then refreshes its view models (cabinet, favourites, shopping, take, browser).

---

## 4. App (`ios/NorseMixology`)

### Settings → Backup (new section)

- **Export backup:** builds the file in a temporary directory off the main actor, showing progress for large photo sets, then presents the share sheet. The file is named `Norse Mixology Backup <date>.norsebackup`. On success it records "Last exported: <date>" in `UserDefaults`.
- **Restore from backup:** opens `.fileImporter` for the `.norsebackup` type, reads the manifest, and shows a confirmation sheet: "Backup from 17 Oct 2026: 24 bottles, 8 favourites, 3 on your shopping list, 5 recipe notes with 12 photos. Restoring replaces everything on this phone." It has a destructive **Restore** button and **Cancel**. Then it validates and restores, with a success haptic and a VoiceOver announcement.
- **Reminder:** the caption "Last exported: never" or "… 3 weeks ago". Once the user has any take and hasn't exported for 30 days, the caption is highlighted. No notifications.

### File type

- An exported type `dev.martinloeseth.norsemixology.backup` (extension `norsebackup`, conforming to `public.data`) is declared in `Info.plist` under `UTExportedTypeDeclarations`.
- It does **not** conform to `public.zip-archive`, so Files doesn't offer to unzip it. It's still a plain ZIP for anyone who renames it.
- Opening a `.norsebackup` from Files or Mail straight into the app (document type plus `onOpenURL`) is a follow-up.

### Wiring

- The exporter and restorer take the app's `ModelContainer`.
- New app files go through `xcodegen generate`; the App workflow now fails on project drift, so the regenerated project must be committed.
- New strings go into `Localizable.xcstrings` via `sync-strings.sh`.

---

## 5. Failure modes

| Failure | Behaviour | Test |
|---|---|---|
| Not a ZIP, or no manifest | "This isn't a Norse Mixology backup", nothing changed | Reader test |
| Newer `formatVersion` | "Made by a newer version of Norse Mixology. Update the app to restore it" | Reader test |
| Truncated or corrupt archive | `damaged`, nothing changed | Reader test with a cut-off file |
| Duplicate IDs, counts mismatch, missing photo file | `damaged`, nothing changed | Reader tests |
| Photo that isn't an image | `photoUnreadable`, nothing changed | Reader test with junk bytes |
| Path traversal (`../x`), oversize entry, zip bomb | Entry ignored or `tooLarge`, nothing changed | Reader tests with crafted archives |
| Save fails mid-restore | Rolled back. The store and preferences are exactly as before | Restorer test with a failing save |
| App killed during restore | Nothing is saved before the single `save()`, so the old data remains | Covered by the single-save design. Manual kill test |
| Recipe or style no longer in the catalog | Restored as ghost items with cached names, as today | Restorer test |
| More than 6 photos for a recipe, notes too long, rating out of range | Normalised as in §3, or rejected | Reader tests |
| Export with no data | Allowed. The file restores to an empty app | Round-trip test |
| Very large photo set | Streamed both ways; memory stays bounded | Performance test with about 200 generated photos |
| Export interrupted (app backgrounded) | Temporary file discarded; "Last exported" not updated | Manual |
| Disk full during export or import | Clear error; temporary files cleaned up; data untouched | Manual |

---

## 6. Testing

- **Core (`BackupTests`, runs in the `swift test` workflow):**
  - a round trip (populate an in-memory store, export, restore into a fresh store, then compare every record, photo bytes and preference);
  - every reader validation and guard in §3 and §5;
  - restore atomicity with an injected save failure;
  - format-version handling;
  - manifest counts.
- **Fixture:** a committed version-1 `.norsebackup` fixture, so later formats must keep reading it.
- **Simulator:** export with a few photos, delete the app, reinstall, restore, then check the takes, photos, cabinet and pantry. Also open the file in Files to check it shows as a Norse Mixology backup.

---

## 7. Decisions (2026-10-17)

1. **Container: ZIP via ZIPFoundation.** [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT, Swift-native, streaming read and write) is added to `NorseMixologyCore` beside GRDB. A standard ZIP can be inspected anywhere and read by a future Android app.
   - Rejected: Apple Archive. It needs no dependency, but the format is Apple-only.
2. **Restore: replace everything.** After the confirmation, the phone ends up exactly like the backup. This suits the main use, a new phone or a reinstall.
   - Rejected for now: merging. It needs per-record rules the user has to understand, such as whether a bottle deleted on one device comes back. It can be added later as a second button without changing the file format.

## 8. Out of scope

iCloud sync and automatic backups (E, part 2); opening a backup directly from Files or Mail; partial restore (only takes, for example); encryption or password protection; Android.
