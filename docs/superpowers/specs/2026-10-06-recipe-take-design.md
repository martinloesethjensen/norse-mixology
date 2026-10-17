# Recipe "My Take" — Notes, Rating, Photos — Design

**Date:** 2026-10-06
**Status:** Approved design, pending implementation plan
**Scope:** iOS only. Sub-project **C** of the post-MVP roadmap (see `2026-10-04-recipe-catalog-browse-design.md` §7). The "made it" log is deliberately not part of this release.

---

## 1. Goal and decisions

Let the user keep their own **rating**, **notes** and **photos** on any catalog recipe, entirely on the device. This is the first data in the app that **cannot be rebuilt from the catalog**, so the design is failure-first: nothing the user typed or added may be lost silently, and a catalog update must never touch it.

| Decision | Choice | Why |
|---|---|---|
| Structure | **One "My take" per recipe** (one rating, one notes box, a photo strip) | Simple to read, edit and back up. A per-time-made log can come later |
| Photos | **A resized copy kept inside the app** (full ≤ 1600 px JPEG + ~320 px thumbnail), picked with `PhotosPicker` | Survives deleting the original, needs no photo-library permission (the system picker hands over only the chosen pictures), can be backed up later |
| Storage | Two SwiftData models keyed by `recipeId`, photo bytes via `@Attribute(.externalStorage)` | SwiftData owns the files, so deleting a record can never orphan one; also the shape iCloud sync (roadmap E) can carry |
| Surfacing | Read-only stars and a "Note / N photos" marker on recipe cards and rows; a "My ratings" filter group | Find favourites without a new screen |
| Header | The first photo, blurred and darkened, behind the recipe title; plain when there is no photo or Reduce Transparency is on | Makes the recipe feel yours; costs no storage (blurs the stored thumbnail) |
| BlurHash | **Not used** | It solves network latency; these photos are local. Revisit if the catalog ships remote images (memory: `project-blurhash-later`) |

Rejected: loose image files with the database holding filenames (a crash between deleting the record and the file leaves orphans, and sync would not carry the files); one model with an array of photos (rewrites every photo on each keystroke in the notes); a link to the original in the Photos library (disappears when the original is deleted, needs library permission, cannot be backed up).

---

## 2. Core (`NorseMixologyCore`)

### Models

```swift
@Model public final class RecipeTake {
    public var id: UUID
    public var recipeId: UUID = UUID()
    public var recipeName: String = ""      // cached, as in FavouriteRecipe, so a take stays readable if the recipe leaves the catalog
    public var rating: Int = 0              // 0 = none, 1…5
    public var notes: String = ""
    public var updatedAt: Date = Date()
}

@Model public final class RecipePhoto {
    public var id: UUID
    public var recipeId: UUID = UUID()
    public var thumbnail: Data = Data()                       // ~320 px JPEG, read by cards and the header
    @Attribute(.externalStorage) public var full: Data = Data()   // ≤ 1600 px JPEG
    public var dateAdded: Date = Date()
}
```

Defaults on every attribute let SwiftData add both models to an existing store without a custom migration (tested, §5).

### Rules (`TakeLimits`)

- Rating is 0…5; anything else is rejected, not clamped.
- Notes: at most **2,000** characters; longer input is trimmed to the limit.
- Photos: at most **6** per recipe.
- **A take with rating 0, empty notes (after trimming whitespace) and no photos does not exist.** Clearing the last thing deletes the record.
- One take per `recipeId`.

### `PhotoProcessor`

`process(_ data: Data) throws -> (full: Data, thumbnail: Data)` using ImageIO (`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`), so a very large image is **downsampled without decoding the full-size bitmap**. Output JPEG quality ≈ 0.8; the orientation is applied (`kCGImageSourceCreateThumbnailWithTransform`). Throws `PhotoError.unreadable` for empty or undecodable data. Pure function, tested on macOS with generated images.

### `RecipeTakeService` and `RecipeTakeViewModel`

`RecipeTakeService` (SwiftData access, caller owns the context, every mutation saved immediately, like `FavouritesService`): `take(for:)`, `setRating`, `setNotes`, `addPhoto`, `removePhoto`, `photos(for:)` (ordered by `dateAdded`), `ratings()`, `photoCounts()`, and the empty-take cleanup.

`RecipeTakeViewModel` (`@Observable`, injected at the app root beside the Favourites and Cabinet view models):
- Dictionaries for lists, refreshed on every mutation: `ratings: [UUID: Int]`, `hasNotes: Set<UUID>`, `photoCounts: [UUID: Int]` — list rows never query the database.
- `rating(for:)`, `setRating(_:for:recipe:)` (same value again clears it), `notes(for:)`, `setNotes(_:for:recipe:)`, `photos(for:) -> [PhotoItem]` (thumbnail + id only), `fullImage(id:) -> Data?`, `addPhotos(_ items: [Data], for:recipe:) -> AddPhotosResult` (`added`, `failed`, `refusedForLimit`), `removePhoto(id:)`.
- Image processing runs off the main actor; results are applied back on it.

### Filter

`RecipeFilter.Criterion` gains `.myRating(.rated)` and `.myRating(.fourOrMore)`; `matches(_:index:ratings:)` takes an optional ratings dictionary (default `[:]`, so existing callers are unchanged). Both criteria form one group (OR within the group, AND with other groups, as today). `.fourOrMore` implies rated.

---

## 3. App (`ios/NorseMixology`)

### Recipe screen — `RecipeDetailView` (shared by the Recipes tab and Favourites)

- **Header:** the user's stars (read-only) after the method/difficulty pills when rated. The **first photo, blurred and darkened,** fills the area behind the title block and scrolls away with the content; the overlay is a fixed dark (or, in light mode, light) wash strong enough for the text to keep its contrast on any photo. With **Reduce Transparency** on, or with no photos, the header is plain, exactly as today.
- **"My take" section after Method:**
  - **Rating:** five 44 pt stars; tapping sets, tapping the same star clears; a caption reads "4 of 5" or "Not rated"; VoiceOver sees one adjustable control ("Your rating, 4 of 5").
  - **Notes:** a growing `TextEditor` in a surface card, placeholder "What would you change? What did you serve it with?". Saved after a 0.6 s pause in typing, when the screen disappears, and when the scene becomes inactive. A counter appears from 1,800 characters. A Done button dismisses the keyboard.
  - **Photos:** a horizontal strip of 88 pt thumbnails plus an "Add photo" tile that opens `PhotosPicker` (images only, selection limit = free slots). Tapping a thumbnail opens a full-screen viewer (swipe between photos, Delete with confirmation, Done). Partial failures read "2 of 3 added"; a full strip shows "6 photos is the limit" instead of the tile.

### Lists

- `RecipeCardView` and `CatalogRowView` show small read-only stars beside the heart and, only when present, a quiet "Note" and "N photos" marker. Nothing is drawn for untouched recipes.
- `RecipeFilterSheet` gets a "My ratings" group (Rated, 4 stars or more); chips read "Rated" and "4 stars or more".

### Wiring

`ModelContainer(for: CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self, RecipeTake.self, RecipePhoto.self)`; one `RecipeTakeViewModel` created at the app root and injected; `RecipeBrowserViewModel` passes `take.ratings` to the filter. New app files are registered with `xcodegen generate`; new strings go into `Localizable.xcstrings` via `sync-strings.sh`.

---

## 4. Failure modes

| Failure | Behaviour | Test |
|---|---|---|
| Existing store (cabinet, favourites, shopping list) opened with the two new models | Lightweight migration; all existing data intact | On-disk store built with the old schema, reopened with five models |
| 48 MP photo | Downsampled via ImageIO, never decoded at full size; result ≤ 1600 px | Processor test with a large generated image |
| Corrupt, empty or non-image data | `PhotoError.unreadable`; nothing stored; user sees "Couldn't add that photo" | Processor + view-model tests |
| Several photos picked, one unreadable | The readable ones are added; `failed` count reported ("2 of 3 added") | View-model test |
| Seventh photo | Refused (`refusedForLimit`), message shown, nothing dropped silently | View-model test |
| Rating outside 1…5 | Rejected | Service test |
| Same star tapped again | Clears the rating | View-model test |
| Notes over 2,000 characters | Trimmed to the limit | Service test |
| Last of rating/notes/photos removed | The take record is deleted; no empty records | Service test |
| Save fails (disk full) | The change stays pending in the context; the view model reports the error; nothing is claimed saved | Manual check; save path wrapped and surfaced |
| App killed while typing | At most the last 0.6 s of text lost; also saved on scene-inactive | Manual check |
| Recipe leaves the catalog | Take and photos stay stored (cached `recipeName`); never shown, never deleted | Service test on a take whose recipe is absent |
| Many rated recipes in lists | Rows read dictionaries and thumbnails only; full images are read only in the viewer | Code review; thumbnails are separate attribute |
| Large Dynamic Type | Stars stay 44 pt, strip and caption reflow, no clipped text | Simulator at the largest size |
| Reduce Transparency | Header stays plain | Manual check |
| Bright photo behind the title | Fixed overlay keeps text readable | Simulator with a white image |
| Deleting a photo by mistake | Confirmation before delete | Manual check |

---

## 5. Testing

- **Core:** `RecipeTakeServiceTests` (rules, limits, empty-take deletion, one take per recipe, orphan recipe), `PhotoProcessorTests` (generated large/small/corrupt/empty images, orientation, size ceilings), `RecipeTakeViewModelTests` (dictionaries refresh, clear-on-same-star, add/remove/limit/partial failure), migration test, `RecipeFilterTests` additions for the rating criteria, and the existing refresh-pipeline budget test extended with the ratings lookup.
- **Simulator (the controller runs it):** rate, write a note, add photos through the real picker, open the viewer, delete a photo, header with a bright photo, cards and rows, the filter, largest text size, Reduce Transparency, relaunch persistence.

---

## 6. Out of scope

Taking a photo with the camera, the per-time "made it" log, searching notes, sharing or exporting a take, photo captions or re-ordering, backup and iCloud (the next roadmap item — this design keeps everything in SwiftData so it can follow), BlurHash, Android.
