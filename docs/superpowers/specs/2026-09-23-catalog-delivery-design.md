# Catalog Delivery — Design

**Date:** 2026-09-23
**Status:** Approved design, pending implementation plan
**Scope:** First "backend" release — over-the-air updates for the taxonomy and recipe catalog, iOS client only.

---

## 1. Goal and decisions

Let both apps pick up new/edited taxonomy and recipes **without an app release**, while staying fully offline-first. Matching stays on-device. The design must leave room for a later server-side `POST /api/v1/recipes/match` ("B") without reworking the content pipeline.

Guiding principle: **failure first.** Every link in the chain has a named failure mode, a defined behaviour, and a test that injects it. Invariant: *the app always has a working catalog, and user data is never at risk.*

| Decision | Choice | Why |
|---|---|---|
| Transport format | JSON over HTTPS | Clients only *parse data* with strict typed decoders; no untrusted executable formats (e.g. downloaded `.sqlite` files) |
| Hosting | Static **GitHub Pages**, public `norse-catalog` repo | Read-only public catalog (~330 KB) needs no server; free, CDN-backed, HTTPS, ETag support |
| Rust service | **Deferred** until B is built | Nothing in this release requires server logic |
| Source of truth | `norse-catalog` repo owns `generate.py` | One source of truth; no cross-repo deploy tokens |
| On-device store | Separate **`catalog.sqlite`** (GRDB on iOS; Room on Android later), built on-device from validated JSON | Read-only catalog replaced wholesale → atomic file swap isolates failures from the live catalog and from user data |
| Apply timing | New catalog applies on **next cold launch** | Nothing changes under open screens; `TaxonomyStore` keeps its load-once model |

---

## 2. Catalog repo and publishing pipeline

### Repo layout (`norse-catalog`, public, catalog content only)

```
norse-catalog/
├── generate.py          # moved from app repo seed-data/
├── catalog/validate.py  # invariant checks
├── catalog/build.py     # generate → validate → write site/ (run locally, output committed)
├── site/v1/             # committed published output (retains last 3 versions)
└── .github/workflows/
    ├── check.yml        # on PR + push: tests; fail if site/ is stale vs generate.py
    └── publish.yml      # on push to main: same checks, then deploy site/ to Pages
```

CI never writes to the repo: the author runs `python3 -m catalog.build` and commits `site/`; CI re-runs the (idempotent) build and fails if it would change anything. No write tokens, no bot commits to a protected branch.

### Published layout

```
/v1/manifest.json                 ← the only mutable file
/v1/taxonomy.<sha8>.json          ← content-hashed, immutable
/v1/recipes.<sha8>.json           ← content-hashed, immutable
```

`<sha8>` is the first 8 hex characters of the file's SHA-256.

```jsonc
// manifest.json
{
  "schemaVersion": 1,                       // JSON contract version; breaking change → /v2/
  "contentVersion": "a1b2c3d4",             // first 8 hex of sha256(taxonomy sha256 + recipes sha256)
  "generatedAt": "2026-09-23T10:00:00Z",    // ISO-8601 UTC
  "taxonomy": { "path": "taxonomy.a1b2c3d4.json", "sha256": "<64 hex>", "bytes": 84264 },
  "recipes":  { "path": "recipes.9f8e7d6c.json",  "sha256": "<64 hex>", "bytes": 242179 }
}
```

The JSON file shapes are exactly today's `taxonomy.json` / `recipes.json` (see Data Model doc).

**Why hashed filenames:** Pages' CDN caches for ~10 minutes. With fixed names a client could fetch a new taxonomy alongside a stale recipes file. The manifest pins exact files and the client verifies hashes, so it gets a consistent pair or nothing.

**Version retention:** `build.py` keeps the hashed files referenced by the current and previous 2 manifests in `site/v1/` and prunes older ones, so a CDN-stale manifest never points at a missing file.

### `validate.py` invariants

- All IDs are valid, unique UUIDs across the taxonomy and across recipes.
- Every family/style references an existing parent; a style's `categoryId` matches its family's category.
- Every recipe ingredient references an existing style.
- Every flavour dimension (except `abv`) is within 0–1; `abvMin ≤ abvMax`.
- Required fields present and non-empty (names, ingredients, steps).
- Each output file ≤ 1 MB (well under the client's 2 MB cap).

Validation runs on every PR (`check.yml`) and gates publishing (`publish.yml`).

### Schema evolution

Additive changes (new optional fields) stay in `/v1/`. A breaking change publishes to `/v2/` while `/v1/` stays frozen at its last version so older app builds keep working.

### Hosting URL (verified 2026-09-23)

The owner's GitHub user site has a custom domain behind Cloudflare, so `martinloesethjensen.github.io/norse-catalog/` answers with a 301 to **plain http** on `martinloeseth.dev`, which App Transport Security would block. Clients therefore use `https://martinloeseth.dev/norse-catalog/` directly (valid TLS, ETag + 304 verified). Cloudflare's bot filtering sits in front: it returned 403 to Python's `urllib` user agent but 200 to CFNetwork and curl. If it ever challenges app traffic, refreshes fail and the app keeps its current catalog (rows 4/7). Recommended: a Cloudflare rule that skips bot protection for `/norse-catalog/*`.

### Repo security

2FA on the owning account; branch protection on `main` (PR + passing `check.yml` required); Pages deploys only via the `publish.yml` Action.

---

## 3. App-repo sync script

`scripts/sync-catalog.sh` fetches the live `/v1/manifest.json` and its two files, verifies hashes, and writes `manifest.json`, `taxonomy.json`, `recipes.json` into **both** `seed-data/` and `ios/NorseMixology/Resources/`. `seed-data/` stays as the synced snapshot because the (paused) Android build copies its JSON at build time and an Android unit test asserts the iOS resources are byte-identical to it; only `generate.py` leaves the app repo. Run manually before a release; the bundled snapshot is the app's last-known-good fallback.

---

## 4. On-device SQLite catalog (iOS)

### Schema

`STRICT` tables, `PRAGMA foreign_keys = ON`, `PRAGMA user_version = 1` (DB schema version, independent of the JSON `schemaVersion`). Constraint violations fail the import.

```sql
CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;
  -- keys: schemaVersion, contentVersion, generatedAt, source ('bundled' | 'remote'), etag (remote only)

CREATE TABLE category (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, sort_order INTEGER NOT NULL) STRICT;

CREATE TABLE family (
  id TEXT PRIMARY KEY,
  category_id TEXT NOT NULL REFERENCES category(id),
  name TEXT NOT NULL, sort_order INTEGER NOT NULL) STRICT;

CREATE TABLE style (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES family(id),
  category_id TEXT NOT NULL REFERENCES category(id),
  name TEXT NOT NULL, sort_order INTEGER NOT NULL,
  abv_min REAL NOT NULL, abv_max REAL NOT NULL,
  sweetness REAL NOT NULL CHECK (sweetness BETWEEN 0 AND 1),
  bitterness REAL NOT NULL CHECK (bitterness BETWEEN 0 AND 1),
  smokiness REAL NOT NULL CHECK (smokiness BETWEEN 0 AND 1),
  citrus REAL NOT NULL CHECK (citrus BETWEEN 0 AND 1),
  floral REAL NOT NULL CHECK (floral BETWEEN 0 AND 1),
  spice REAL NOT NULL CHECK (spice BETWEEN 0 AND 1),
  herbal REAL NOT NULL CHECK (herbal BETWEEN 0 AND 1),
  fruity REAL NOT NULL CHECK (fruity BETWEEN 0 AND 1),
  oaky REAL NOT NULL CHECK (oaky BETWEEN 0 AND 1),
  abv REAL NOT NULL) STRICT;

CREATE TABLE style_brand (
  style_id TEXT NOT NULL REFERENCES style(id), position INTEGER NOT NULL, brand TEXT NOT NULL,
  PRIMARY KEY (style_id, position)) STRICT;

CREATE TABLE recipe (
  id TEXT PRIMARY KEY, sort_order INTEGER NOT NULL,
  name TEXT NOT NULL, description TEXT NOT NULL, glass_type TEXT NOT NULL, method TEXT NOT NULL,
  difficulty TEXT NOT NULL, image_url TEXT,
  sweetness REAL NOT NULL CHECK (sweetness BETWEEN 0 AND 1),
  bitterness REAL NOT NULL CHECK (bitterness BETWEEN 0 AND 1),
  smokiness REAL NOT NULL CHECK (smokiness BETWEEN 0 AND 1),
  citrus REAL NOT NULL CHECK (citrus BETWEEN 0 AND 1),
  floral REAL NOT NULL CHECK (floral BETWEEN 0 AND 1),
  spice REAL NOT NULL CHECK (spice BETWEEN 0 AND 1),
  herbal REAL NOT NULL CHECK (herbal BETWEEN 0 AND 1),
  fruity REAL NOT NULL CHECK (fruity BETWEEN 0 AND 1),
  oaky REAL NOT NULL CHECK (oaky BETWEEN 0 AND 1),
  abv REAL NOT NULL) STRICT;

CREATE TABLE recipe_ingredient (
  recipe_id TEXT NOT NULL REFERENCES recipe(id), position INTEGER NOT NULL,
  style_id TEXT NOT NULL REFERENCES style(id),
  amount TEXT NOT NULL, preparation TEXT,
  is_optional INTEGER NOT NULL CHECK (is_optional IN (0, 1)),
  substitute_notes TEXT,
  PRIMARY KEY (recipe_id, position)) STRICT;

CREATE TABLE recipe_step (
  recipe_id TEXT NOT NULL REFERENCES recipe(id), position INTEGER NOT NULL, text TEXT NOT NULL,
  PRIMARY KEY (recipe_id, position)) STRICT;

CREATE TABLE recipe_tag (
  recipe_id TEXT NOT NULL REFERENCES recipe(id), position INTEGER NOT NULL, tag TEXT NOT NULL,
  PRIMARY KEY (recipe_id, position), UNIQUE (recipe_id, tag)) STRICT;
CREATE INDEX recipe_tag_by_tag ON recipe_tag(tag);
```

`sort_order` / `position` preserve JSON array order so models read back from the DB equal those parsed from JSON.

### Components (new `Catalog/` folder in `NorseMixologyCore`)

| Unit | Responsibility | Depends on |
|---|---|---|
| `CatalogPaths` | Locations in Application Support: `catalog.sqlite`; per-attempt staging URL (`catalog.new.<uuid>.sqlite`); staging cleanup; promote staging → live | — |
| `CatalogImporter` | `(manifest, taxonomyData, recipesData, destination)` → decode with existing decoders, reject if any row is skipped, create schema, insert everything in one transaction, run `PRAGMA foreign_key_check` + `integrity_check`. Verifies file hashes. Throws typed `CatalogError` | GRDB, existing JSON decoders |
| `CatalogDatabase` | Opens the live DB **read-only**, checks `user_version`, loads everything into existing `[IngredientCategory]` / `[Recipe]` model types plus `catalog_meta`, then closes (the catalog lives in memory in `TaxonomyStore`, so no long-lived connection) | GRDB |
| `CatalogBootstrap` | Launch-time decision (see §5 rows 11, 13–15, 17); always yields an open `CatalogDatabase` or an explicit unavailable state | Paths, Importer, Database |
| `CatalogUpdater` | Background refresh (§5 rows 6–12): manifest → caps → download → hash → import to `catalog.new.<uuid>.sqlite` → atomic replace | injected `URLSession`, Importer, Paths |

`CatalogImporter` is the **only** writer and the only path into the DB — used for both the first-launch bundled import and remote updates.

**Integration:** `TaxonomyStore` keeps its public API; its source switches from parsing bundled JSON to reading `CatalogDatabase`. Views, view models and `MatchingService` are unchanged. The DB is rebuilt on-device from the bundled JSON on first launch (~158 recipes; expected to take milliseconds), so no prebuilt `.sqlite` ships in the bundle.

**Configuration:** the catalog base URL (`https://martinloeseth.dev/norse-catalog/`) is a single Swift constant in the app target (`CatalogConfig.baseURL`) — the project generates its Info.plist, which doesn't take arbitrary keys. HTTPS enforced by App Transport Security defaults. Downloads are held in memory (≤ 2 MB each), so there is no download temp directory.

---

## 5. Client flow and failure modes

### Launch (`CatalogBootstrap`)

1. Delete leftover staging files (`catalog.new*`).
2. Open `catalog.sqlite` read-only. If missing, unopenable, `user_version` ≠ expected, or its `generatedAt` is older than the bundled `manifest.json`'s → rebuild from bundled JSON via `CatalogImporter`, then swap in.
3. Hand the open `CatalogDatabase` to `TaxonomyStore`.

### Background refresh (`CatalogUpdater`, after UI is up, every cold launch)

1. `GET /v1/manifest.json` with `If-None-Match` (ETag stored in `catalog_meta`). `304`, unchanged `contentVersion`, or a `generatedAt` not newer than the current catalog's → stop (the last rule stops a CDN-stale manifest from downgrading a newer catalog).
2. Reject if `schemaVersion` unsupported or either `bytes` > 2 MB.
3. Download both files (cap enforced while streaming), verify SHA-256.
4. `CatalogImporter` → `catalog.new.<uuid>.sqlite`.
5. Atomically replace `catalog.sqlite` (`FileManager.replaceItemAt`); the new ETag is stored in the new DB's `catalog_meta`, so it can never disagree with the catalog it describes. Takes effect next cold launch — the current session's read-only connection keeps its already-loaded data.

Any failure: log via `AppLog.catalog`, discard temp artifacts, keep the current catalog. No user-facing errors; the UI never waits on the network.

### Failure-mode table

Each row has at least one test that injects the failure.

| # | Failure | Behaviour | Test approach |
|---|---|---|---|
| 1 | Generator emits invalid data | `validate.py` fails PR / publish; nothing deploys | `validate.py` unit tests with broken fixtures |
| 2 | CDN serves old manifest while new files are live | Last 3 versions' hashed files retained; client ignores a manifest whose `generatedAt` isn't newer than its current catalog | `build.py` retention test after 4 builds; updater test with an older `generatedAt` |
| 3 | Valid-but-wrong content published | Revert commit → republish; new `contentVersion` propagates | Runbook in repo README; covered by row-1/2 pipeline tests |
| 4 | Pages down / repo gone | Current catalog kept; silent | `URLProtocol` stub: 404 / 5xx / DNS failure |
| 5 | Account compromise → valid malicious content | Limited to catalog text with client bounds checks; 2FA + branch protection. **Accepted risk:** payload signing deferred | — |
| 6 | Offline / timeout (15 s) | Skip; retry next cold launch | Stub: no connection, delayed response |
| 7 | Captive portal returns HTML | Decode / hash fails → reject | Stub: `200` with HTML body |
| 8 | Oversized response | 2 MB cap enforced during streaming | Stub: 3 MB body, and manifest `bytes` over cap |
| 9 | Mismatched file versions | SHA-256 mismatch → reject | Stub: file body ≠ manifest hash |
| 10 | Parse / validation / constraint failure (any skipped row) | Delete `catalog.new.<uuid>.sqlite`; keep current | Fixtures: malformed recipe, dangling style ref, flavour 1.5 |
| 11 | App killed / disk full mid-import | Temp files removed next launch; live DB untouched | Leave partial `catalog.new.<uuid>.sqlite` files, run bootstrap |
| 12 | Swap fails | Old file remains (atomic replace) | Inject replace failure via `CatalogPaths` seam |
| 13 | `catalog.sqlite` corrupt / unopenable | Delete; rebuild from bundled JSON | Fixture: truncated / garbage DB file |
| 14 | App update changes DB schema | `user_version` mismatch → rebuild from bundled; next refresh fetches latest | Fixture DB with `user_version = 0` |
| 15 | Bundled catalog newer than cached (post app update) | Newer `generatedAt` wins | Bootstrap test with older cached DB |
| 16 | Update removes a style in the cabinet / a favourited recipe | Cabinet keeps its snapshot; favourite shows cached name + "no longer in catalog"; matching tolerates unknown style IDs without crashing | `MatchingService` tests with cabinet/recipe IDs absent from the index; favourites view-model test |
| 17 | Bundled rebuild also fails | Keep an older-but-valid live catalog if there is one; otherwise explicit "catalog unavailable" state, no crash | Bootstrap with corrupt bundled fixture; plus a build-time unit test that the real bundled JSON imports cleanly |

Additional test: **round-trip** — bundled JSON → `CatalogImporter` → `CatalogDatabase` yields models equal to those from today's JSON loaders.

---

## 6. Scope

**In scope**
1. `norse-catalog` repo: `generate.py` (moved), `validate.py`, `build.py`, `check.yml`, `publish.yml`, Pages enabled, branch protection.
2. App repo: `scripts/sync-catalog.sh`; bundled `manifest.json`; `seed-data/generate.py` removed (`seed-data/` JSON kept as the synced snapshot).
3. iOS: GRDB dependency; `Catalog/` components; `TaxonomyStore` switched to `CatalogDatabase`; bootstrap + updater wired into app launch.
4. Tests for every failure row plus the round-trip test.

**Out of scope**
- Android (paused). It adopts the same JSON contract later via a separate Room catalog database; nothing server-side is iOS-specific.
- Payload signing (accepted risk, row 5).
- Mid-session hot swap of the catalog.
- Any server code, database server, accounts or sync.

---

## 7. Room for B (`POST /api/v1/recipes/match`)

When B is built, a small Rust service reads `manifest.json` and the hashed files from Pages at startup (and re-checks on an interval), holding the catalog in memory. The catalog pipeline is unchanged, and the request/response contract in *System Design (Rust Backend)* §3 is unaffected. The shared-matching-logic question (System Design §6) remains open; this design does not commit to an answer.

---

## 8. Docs to update on implementation

- *Backend (Rust) – Future Release* and *System Design (Rust Backend)*: content delivery is static hosting; the Rust service arrives with B; Postgres not needed for read-only content.
- *Deployment*: add `norse-catalog` repo, Pages, and the sync-script release step.
- *Data Model*: the catalog is stored in an on-device SQLite database.
- `NORSE_MIXOLOGY_BUILD.md`: catalog architecture section.
