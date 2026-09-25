# iOS SQLite Catalog & Over-the-Air Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the iOS app's taxonomy and recipe catalog into an on-device `catalog.sqlite` built from validated JSON, and refresh it from GitHub Pages without an app release, with every failure mode falling back to a working catalog.

**Architecture:** A new `Catalog/` module in `NorseMixologyCore`. `CatalogImporter` is the only writer: it verifies hashes, decodes with the existing JSON decoders, and builds a fresh SQLite file in one transaction under `STRICT` tables with foreign keys and `CHECK` constraints. `CatalogDatabase` reads it back (read-only) into the existing model types. `CatalogBootstrap` picks or rebuilds the catalog at launch; `CatalogUpdater` downloads a newer manifest + files in the background and atomically swaps the new database in for the next launch. `TaxonomyStore`'s consumers are unchanged.

**Tech Stack:** Swift 6.4 toolchain (package in Swift 5 language mode, tools 5.9), GRDB.swift 7, CryptoKit, URLSession, XCTest, xcodegen.

**Spec:** `/Users/mlj/dev/norse-mixology/docs/superpowers/specs/2026-09-23-catalog-delivery-design.md` (§3–§6)

**This is Plan 2 of 2.** Tasks 1–7 and 9 need nothing from Plan 1. **Task 8 requires Plan 1 to be finished** (`https://martinloeseth.dev/norse-catalog/v1/manifest.json` live).

## Global Constraints

- iOS 17 minimum; package platforms `.iOS(.v17), .macOS(.v14)` unchanged — core tests run on macOS with `swift test`.
- Android is paused: do not modify anything under `android/`.
- Catalog base URL: `https://martinloeseth.dev/norse-catalog/`; manifest at `v1/manifest.json`.
- Supported manifest `schemaVersion`: `1`. Client file cap: `2_000_000` bytes per catalog file; manifest cap `65_536` bytes.
- Hashed file names must match `^(taxonomy|recipes)\.[0-9a-f]{8}\.json$`; `sha256` must match `^[0-9a-f]{64}$`.
- DB schema version (`PRAGMA user_version`): `1`.
- File locations: `Application Support/Catalog/catalog.sqlite` (live), `Application Support/Catalog/catalog.new.sqlite` (staging).
- Network: 15 s request timeout, ephemeral session, no URL cache; the app never waits on the network; failures are logged via `AppLog.catalog`, never shown to users.
- A new catalog applies on the **next** cold launch.
- Logging: `os.Logger` via `AppLog.catalog` only — no `print`. Interpolate error descriptions with `privacy: .public` (they contain no user data).
- Dates in `catalog_meta` and manifests are whole-second ISO-8601 UTC (`2026-09-23T10:00:00Z`). Test fixtures must use whole-second dates.
- Every failure row 1–17 in spec §5 must have a test; this plan covers rows 2 (client side) and 4–17.

## Commands

- Core tests: `cd /Users/mlj/dev/norse-mixology/ios/Packages/NorseMixologyCore && swift test` (baseline before this plan: 70 tests, 0 failures).
- Single test class: `swift test --filter CatalogImporterTests`.
- App build: `cd /Users/mlj/dev/norse-mixology/ios && xcodegen generate && xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build`

---

## File Structure

```
ios/Packages/NorseMixologyCore/
├── Package.swift                                  # + GRDB dependency
├── Sources/NorseMixologyCore/
│   ├── Catalog/
│   │   ├── CatalogError.swift                     # one typed error for the module
│   │   ├── CatalogManifest.swift                  # manifest model, decode + validate
│   │   ├── CatalogMeta.swift                      # CatalogMeta, CatalogSource, LoadedCatalog, date + hash helpers
│   │   ├── CatalogSchema.swift                    # DDL, user_version
│   │   ├── CatalogImporter.swift                  # the only writer
│   │   ├── CatalogDatabase.swift                  # read-only loader
│   │   ├── CatalogPaths.swift                     # file locations, staging cleanup, promote
│   │   ├── CatalogBootstrap.swift                 # launch-time decision
│   │   └── CatalogUpdater.swift                   # background refresh
│   ├── Services/MatchingService.swift             # ghost-style fix (Task 7)
│   └── Taxonomy/TaxonomyStore.swift               # load(categories:recipes:), isUnavailable
└── Tests/NorseMixologyCoreTests/
    ├── CatalogFixtures.swift
    ├── StubURLProtocol.swift
    ├── CatalogSchemaTests.swift
    ├── CatalogManifestTests.swift
    ├── CatalogImporterTests.swift
    ├── CatalogDatabaseTests.swift
    ├── CatalogBootstrapTests.swift
    ├── CatalogUpdaterTests.swift
    ├── CatalogToleranceTests.swift
    ├── AppBundleCatalogTests.swift
    └── TaxonomyStoreTests.swift                   # + 2 tests
ios/NorseMixology/
├── Catalog/CatalogLaunch.swift                    # app-side glue: bundle, paths, base URL
├── NorseMixologyApp.swift                         # uses CatalogLaunch
├── ContentView.swift                              # unavailable state
└── Resources/manifest.json                        # synced (Task 8)
scripts/sync-catalog.sh                            # repo root (Task 8)
seed-data/generate.py                              # deleted (Task 8)
```

---

### Task 1: GRDB dependency, error type, and schema

**Files:**
- Modify: `ios/Packages/NorseMixologyCore/Package.swift`
- Create: `Sources/NorseMixologyCore/Catalog/CatalogError.swift`, `Sources/NorseMixologyCore/Catalog/CatalogSchema.swift`
- Test: `Tests/NorseMixologyCoreTests/CatalogSchemaTests.swift`

(All `Sources/` and `Tests/` paths in this plan are relative to `ios/Packages/NorseMixologyCore/`.)

**Interfaces:**
- Produces: `public enum CatalogError: Error, Equatable, Sendable` with cases `invalidManifest(String)`, `unsupportedSchemaVersion(Int)`, `fileTooLarge(String, Int)`, `hashMismatch(String)`, `malformedTaxonomy(String)`, `malformedRecipes(String)`, `invalidStructure(String)`, `constraintViolation(String)`, `missingDatabase`, `schemaMismatch(found: Int)`, `corruptDatabase(String)`, `http(status: Int)`, `transport(String)`, `fileSystem(String)`.
- Produces: `enum CatalogSchema` (internal) — `static let version = 1`, `static let profileColumns: [String]` (9 flavour dims + `abv`), `static func profileValues(_: FlavorProfile) -> [Double]`, `static func create(in: Database) throws`.

- [ ] **Step 1: Add GRDB to the package**

Replace `Package.swift` with:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NorseMixologyCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NorseMixologyCore",
            targets: ["NorseMixologyCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "NorseMixologyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "NorseMixologyCoreTests",
            dependencies: ["NorseMixologyCore"],
            resources: [.copy("Resources/taxonomy.json"), .copy("Resources/recipes.json")]
        )
    ]
)
```

Run: `cd /Users/mlj/dev/norse-mixology/ios/Packages/NorseMixologyCore && swift package resolve && swift build`
Expected: resolves GRDB 7.x and builds.

- [ ] **Step 2: Write the failing schema tests**

`Tests/NorseMixologyCoreTests/CatalogSchemaTests.swift`:

```swift
import XCTest
import GRDB
@testable import NorseMixologyCore

final class CatalogSchemaTests: XCTestCase {
    private func makeDatabase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { try CatalogSchema.create(in: $0) }
        return queue
    }

    private let categoryId = UUID().uuidString
    private let familyId = UUID().uuidString

    private func insertCategoryAndFamily(_ db: Database) throws {
        try db.execute(sql: "INSERT INTO category (id, name, sort_order) VALUES (?, 'Spirit', 0)", arguments: [categoryId])
        try db.execute(sql: "INSERT INTO family (id, category_id, name, sort_order) VALUES (?, ?, 'Gin', 0)", arguments: [familyId, categoryId])
    }

    private func insertStyle(_ db: Database, citrus: Double = 0.3, familyId overrideFamily: String? = nil) throws {
        var args: [(any DatabaseValueConvertible)?] = [UUID().uuidString, overrideFamily ?? familyId, categoryId, "London Dry Gin", 0, 37.5, 47.0]
        let profile = FlavorProfile(sweetness: 0.1, bitterness: 0.2, smokiness: 0, citrus: citrus, floral: 0.2, spice: 0.1, herbal: 0.7, fruity: 0.1, oaky: 0, abv: 42)
        args.append(contentsOf: CatalogSchema.profileValues(profile).map { $0 as (any DatabaseValueConvertible)? })
        let columns = (["id", "family_id", "category_id", "name", "sort_order", "abv_min", "abv_max"] + CatalogSchema.profileColumns)
        try db.execute(
            sql: "INSERT INTO style (\(columns.joined(separator: ", "))) VALUES (\(Array(repeating: "?", count: columns.count).joined(separator: ", ")))",
            arguments: StatementArguments(args)
        )
    }

    func testCreateSetsUserVersion() throws {
        let queue = try makeDatabase()
        let version = try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }
        XCTAssertEqual(version, CatalogSchema.version)
    }

    func testCreateMakesEveryTable() throws {
        let queue = try makeDatabase()
        let tables = try queue.read { try String.fetchSet($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        XCTAssertEqual(tables, ["catalog_meta", "category", "family", "style", "style_brand",
                                "recipe", "recipe_ingredient", "recipe_step", "recipe_tag"])
    }

    func testValidStyleInserts() throws {
        let queue = try makeDatabase()
        try queue.write { db in
            try insertCategoryAndFamily(db)
            try insertStyle(db)
        }
    }

    func testFlavourOutsideZeroToOneIsRejected() throws {
        let queue = try makeDatabase()
        XCTAssertThrowsError(try queue.write { db in
            try insertCategoryAndFamily(db)
            try insertStyle(db, citrus: 1.5)
        })
    }

    func testDanglingForeignKeyIsRejected() throws {
        let queue = try makeDatabase()
        XCTAssertThrowsError(try queue.write { db in
            try insertCategoryAndFamily(db)
            try insertStyle(db, familyId: UUID().uuidString)
        })
    }

    func testStrictTablesRejectWrongTypes() throws {
        let queue = try makeDatabase()
        XCTAssertThrowsError(try queue.write { db in
            try db.execute(sql: "INSERT INTO category (id, name, sort_order) VALUES ('x', 'Spirit', 'first')")
        })
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter CatalogSchemaTests`
Expected: compile error — `cannot find 'CatalogSchema' in scope`.

- [ ] **Step 4: Implement the error type and schema**

`Sources/NorseMixologyCore/Catalog/CatalogError.swift`:

```swift
import Foundation

/// Every way the catalog pipeline can fail. One type for the whole module so
/// the bootstrap and updater can log and branch on a single, exhaustive set.
public enum CatalogError: Error, Equatable, Sendable {
    case invalidManifest(String)
    case unsupportedSchemaVersion(Int)
    /// File or response name, and its size in bytes.
    case fileTooLarge(String, Int)
    /// "taxonomy" or "recipes".
    case hashMismatch(String)
    case malformedTaxonomy(String)
    case malformedRecipes(String)
    /// A family/style whose parent ids disagree with where it is nested.
    case invalidStructure(String)
    /// SQLite rejected the data: CHECK, NOT NULL, foreign key or integrity failure.
    case constraintViolation(String)
    case missingDatabase
    case schemaMismatch(found: Int)
    case corruptDatabase(String)
    case http(status: Int)
    case transport(String)
    case fileSystem(String)
}
```

`Sources/NorseMixologyCore/Catalog/CatalogSchema.swift`:

```swift
import GRDB

/// DDL for the on-device catalog database. `version` is stored in
/// `PRAGMA user_version`; bump it whenever these statements change — the
/// bootstrap rebuilds any database whose version differs.
enum CatalogSchema {
    static let version = 1

    /// The nine 0–1 flavour dimensions, then `abv` (not range-checked).
    static let profileColumns = ["sweetness", "bitterness", "smokiness", "citrus", "floral",
                                 "spice", "herbal", "fruity", "oaky", "abv"]

    /// Values in `profileColumns` order.
    static func profileValues(_ p: FlavorProfile) -> [Double] {
        [p.sweetness, p.bitterness, p.smokiness, p.citrus, p.floral, p.spice, p.herbal, p.fruity, p.oaky, p.abv]
    }

    private static var profileColumnDefinitions: String {
        profileColumns.map { column in
            column == "abv"
                ? "abv REAL NOT NULL"
                : "\(column) REAL NOT NULL CHECK (\(column) BETWEEN 0 AND 1)"
        }.joined(separator: ",\n  ")
    }

    static var statements: [String] {
        [
            "CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT",
            "CREATE TABLE category (id TEXT PRIMARY KEY, name TEXT NOT NULL, sort_order INTEGER NOT NULL) STRICT",
            """
            CREATE TABLE family (
              id TEXT PRIMARY KEY,
              category_id TEXT NOT NULL REFERENCES category(id),
              name TEXT NOT NULL,
              sort_order INTEGER NOT NULL) STRICT
            """,
            """
            CREATE TABLE style (
              id TEXT PRIMARY KEY,
              family_id TEXT NOT NULL REFERENCES family(id),
              category_id TEXT NOT NULL REFERENCES category(id),
              name TEXT NOT NULL,
              sort_order INTEGER NOT NULL,
              abv_min REAL NOT NULL,
              abv_max REAL NOT NULL,
              \(profileColumnDefinitions)) STRICT
            """,
            """
            CREATE TABLE style_brand (
              style_id TEXT NOT NULL REFERENCES style(id),
              position INTEGER NOT NULL,
              brand TEXT NOT NULL,
              PRIMARY KEY (style_id, position)) STRICT
            """,
            """
            CREATE TABLE recipe (
              id TEXT PRIMARY KEY,
              sort_order INTEGER NOT NULL,
              name TEXT NOT NULL,
              description TEXT NOT NULL,
              glass_type TEXT NOT NULL,
              method TEXT NOT NULL,
              difficulty TEXT NOT NULL,
              image_url TEXT,
              \(profileColumnDefinitions)) STRICT
            """,
            """
            CREATE TABLE recipe_ingredient (
              recipe_id TEXT NOT NULL REFERENCES recipe(id),
              position INTEGER NOT NULL,
              style_id TEXT NOT NULL REFERENCES style(id),
              amount TEXT NOT NULL,
              preparation TEXT,
              is_optional INTEGER NOT NULL CHECK (is_optional IN (0, 1)),
              substitute_notes TEXT,
              PRIMARY KEY (recipe_id, position)) STRICT
            """,
            """
            CREATE TABLE recipe_step (
              recipe_id TEXT NOT NULL REFERENCES recipe(id),
              position INTEGER NOT NULL,
              text TEXT NOT NULL,
              PRIMARY KEY (recipe_id, position)) STRICT
            """,
            """
            CREATE TABLE recipe_tag (
              recipe_id TEXT NOT NULL REFERENCES recipe(id),
              position INTEGER NOT NULL,
              tag TEXT NOT NULL,
              PRIMARY KEY (recipe_id, position),
              UNIQUE (recipe_id, tag)) STRICT
            """,
            "CREATE INDEX recipe_tag_by_tag ON recipe_tag(tag)"
        ]
    }

    static func create(in db: Database) throws {
        for statement in statements {
            try db.execute(sql: statement)
        }
        try db.execute(sql: "PRAGMA user_version = \(version)")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CatalogSchemaTests`
Expected: 6 tests PASS. Then run `swift test` — expected: 76 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Package.swift ios/Packages/NorseMixologyCore/Package.resolved \
  ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Catalog \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogSchemaTests.swift
git commit -m "iOS: GRDB dependency and STRICT catalog schema"
```

(If `Package.resolved` isn't created at that path, drop it from `git add`.)

---

### Task 2: Manifest model and catalog metadata types

**Files:**
- Create: `Sources/NorseMixologyCore/Catalog/CatalogManifest.swift`, `Sources/NorseMixologyCore/Catalog/CatalogMeta.swift`
- Test: `Tests/NorseMixologyCoreTests/CatalogManifestTests.swift`, `Tests/NorseMixologyCoreTests/CatalogFixtures.swift`

**Interfaces:**
- Consumes: `CatalogError` (Task 1).
- Produces:
  - `public struct CatalogManifest: Codable, Equatable, Sendable` — `schemaVersion: Int`, `contentVersion: String`, `generatedAt: Date`, `taxonomy: FileEntry`, `recipes: FileEntry`; memberwise `public init`; `public static let supportedSchemaVersion = 1`, `public static let maxFileBytes = 2_000_000`; `public static func decode(from: Data) throws -> CatalogManifest` (throws `CatalogError`).
  - `public struct CatalogManifest.FileEntry: Codable, Equatable, Sendable` — `path: String`, `sha256: String`, `bytes: Int`; memberwise `public init`.
  - `public enum CatalogSource: String, Sendable { case bundled, remote }`.
  - `public struct CatalogMeta: Equatable, Sendable` — `schemaVersion: Int`, `contentVersion: String`, `generatedAt: Date`, `source: CatalogSource`, `etag: String?`; memberwise `public init`.
  - `public struct LoadedCatalog: Equatable, Sendable` — `meta: CatalogMeta`, `categories: [IngredientCategory]`, `recipes: [Recipe]`.
  - `enum CatalogDate` (internal) — `static func format(_: Date) -> String`, `static func parse(_: String) -> Date?`.
  - `enum CatalogHash` (internal) — `static func sha256Hex(_: Data) -> String`.
  - Test helper `enum CatalogFixtures` (see Step 1) — used by every later test file.

- [ ] **Step 1: Write the shared test fixtures**

`Tests/NorseMixologyCoreTests/CatalogFixtures.swift`:

```swift
import Foundation
import XCTest
@testable import NorseMixologyCore

/// Shared builders for catalog tests. Dates are whole seconds because
/// `catalog_meta` and manifests store whole-second ISO-8601.
enum CatalogFixtures {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func resource(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    static func taxonomyData() throws -> Data { try resource("taxonomy") }
    static func recipesData() throws -> Data { try resource("recipes") }

    /// Bundled recipes JSON with an edit applied.
    static func recipesData(editing edit: (inout [[String: Any]]) -> Void) throws -> Data {
        var recipes = try XCTUnwrap(JSONSerialization.jsonObject(with: recipesData()) as? [[String: Any]])
        edit(&recipes)
        return try JSONSerialization.data(withJSONObject: recipes)
    }

    /// Bundled taxonomy JSON with an edit applied.
    static func taxonomyData(editing edit: (inout [[String: Any]]) -> Void) throws -> Data {
        var categories = try XCTUnwrap(JSONSerialization.jsonObject(with: taxonomyData()) as? [[String: Any]])
        edit(&categories)
        return try JSONSerialization.data(withJSONObject: categories)
    }

    static func entry(_ name: String, _ data: Data) -> CatalogManifest.FileEntry {
        let sha = CatalogHash.sha256Hex(data)
        return CatalogManifest.FileEntry(path: "\(name).\(sha.prefix(8)).json", sha256: sha, bytes: data.count)
    }

    static func manifest(
        taxonomy: Data,
        recipes: Data,
        generatedAt: Date = t0,
        contentVersion: String = "aaaaaaaa"
    ) -> CatalogManifest {
        CatalogManifest(
            schemaVersion: 1,
            contentVersion: contentVersion,
            generatedAt: generatedAt,
            taxonomy: entry("taxonomy", taxonomy),
            recipes: entry("recipes", recipes)
        )
    }

    static func encode(_ manifest: CatalogManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    /// A fresh, empty catalog directory under the temp dir.
    static func tempPaths() throws -> CatalogPaths {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "catalog-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = CatalogPaths(directory: directory)
        try paths.prepareDirectory()
        return paths
    }

    /// Builds a live catalog from the bundled fixture JSON and returns its meta.
    @discardableResult
    static func installLive(
        at paths: CatalogPaths,
        generatedAt: Date = t0,
        contentVersion: String = "aaaaaaaa",
        source: CatalogSource = .bundled,
        etag: String? = nil
    ) throws -> CatalogMeta {
        let taxonomy = try taxonomyData()
        let recipes = try recipesData()
        try CatalogImporter.build(
            at: paths.staging,
            manifest: manifest(taxonomy: taxonomy, recipes: recipes, generatedAt: generatedAt, contentVersion: contentVersion),
            taxonomyData: taxonomy,
            recipesData: recipes,
            source: source,
            etag: etag
        )
        try paths.promoteStaging()
        return try CatalogDatabase.load(from: paths.live).meta
    }
}
```

`tempPaths()` and `installLive` reference `CatalogPaths`, `CatalogImporter` and `CatalogDatabase`, which arrive in Tasks 3–5. So that this task compiles, **add only `t0`, `resource`, `taxonomyData()`, `recipesData()`, both `editing` helpers, `entry`, `manifest` and `encode` now**; Task 3 adds `tempPaths()` and Task 5 adds `installLive` (their full text is above — copy it then).

- [ ] **Step 2: Write the failing manifest tests**

`Tests/NorseMixologyCoreTests/CatalogManifestTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

final class CatalogManifestTests: XCTestCase {
    private let validJSON = """
    {
      "schemaVersion": 1,
      "contentVersion": "a1b2c3d4",
      "generatedAt": "2026-09-23T10:00:00Z",
      "taxonomy": { "path": "taxonomy.0123abcd.json", "sha256": "\(String(repeating: "a", count: 64))", "bytes": 84264 },
      "recipes":  { "path": "recipes.4567ef01.json",  "sha256": "\(String(repeating: "b", count: 64))", "bytes": 242179 }
    }
    """

    private func decode(_ json: String) throws -> CatalogManifest {
        try CatalogManifest.decode(from: Data(json.utf8))
    }

    func testDecodesAValidManifest() throws {
        let manifest = try decode(validJSON)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.contentVersion, "a1b2c3d4")
        XCTAssertEqual(manifest.generatedAt, CatalogDate.parse("2026-09-23T10:00:00Z"))
        XCTAssertEqual(manifest.taxonomy.path, "taxonomy.0123abcd.json")
        XCTAssertEqual(manifest.recipes.bytes, 242179)
    }

    func testHTMLIsAnInvalidManifest() {
        XCTAssertThrowsError(try decode("<html><body>Log in to Wi-Fi</body></html>")) { error in
            guard case CatalogError.invalidManifest = error else { return XCTFail("got \(error)") }
        }
    }

    func testUnsupportedSchemaVersionIsRejected() {
        XCTAssertThrowsError(try decode(validJSON.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2"))) { error in
            XCTAssertEqual(error as? CatalogError, .unsupportedSchemaVersion(2))
        }
    }

    func testOversizedFileIsRejected() {
        XCTAssertThrowsError(try decode(validJSON.replacingOccurrences(of: "242179", with: "2000001"))) { error in
            XCTAssertEqual(error as? CatalogError, .fileTooLarge("recipes.4567ef01.json", 2_000_001))
        }
    }

    func testPathTraversalIsRejected() {
        XCTAssertThrowsError(try decode(validJSON.replacingOccurrences(of: "taxonomy.0123abcd.json", with: "../taxonomy.0123abcd.json"))) { error in
            guard case CatalogError.invalidManifest = error else { return XCTFail("got \(error)") }
        }
    }

    func testMalformedHashIsRejected() {
        XCTAssertThrowsError(try decode(validJSON.replacingOccurrences(of: String(repeating: "a", count: 64), with: "xyz"))) { error in
            guard case CatalogError.invalidManifest = error else { return XCTFail("got \(error)") }
        }
    }

    func testFixtureManifestRoundTripsThroughJSON() throws {
        let manifest = CatalogFixtures.manifest(taxonomy: Data("[]".utf8), recipes: Data("[1]".utf8))
        XCTAssertEqual(try CatalogManifest.decode(from: CatalogFixtures.encode(manifest)), manifest)
    }

    func testDateFormatIsWholeSecondUTC() {
        XCTAssertEqual(CatalogDate.format(CatalogFixtures.t0), "2026-09-21T14:13:20Z")
        XCTAssertEqual(CatalogDate.parse("2026-09-21T14:13:20Z"), CatalogFixtures.t0)
    }

    func testSha256Hex() {
        XCTAssertEqual(CatalogHash.sha256Hex(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter CatalogManifestTests`
Expected: compile error — `cannot find 'CatalogManifest' in scope`.

- [ ] **Step 4: Implement the manifest and meta types**

`Sources/NorseMixologyCore/Catalog/CatalogManifest.swift`:

```swift
import Foundation

/// `/v1/manifest.json` — the only mutable file the catalog host publishes.
/// Everything here is validated before any file it points at is fetched.
public struct CatalogManifest: Codable, Equatable, Sendable {
    public struct FileEntry: Codable, Equatable, Sendable {
        public let path: String
        public let sha256: String
        public let bytes: Int

        public init(path: String, sha256: String, bytes: Int) {
            self.path = path
            self.sha256 = sha256
            self.bytes = bytes
        }
    }

    public static let supportedSchemaVersion = 1
    public static let maxFileBytes = 2_000_000

    public let schemaVersion: Int
    public let contentVersion: String
    public let generatedAt: Date
    public let taxonomy: FileEntry
    public let recipes: FileEntry

    public init(schemaVersion: Int, contentVersion: String, generatedAt: Date, taxonomy: FileEntry, recipes: FileEntry) {
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.generatedAt = generatedAt
        self.taxonomy = taxonomy
        self.recipes = recipes
    }

    public static func decode(from data: Data) throws -> CatalogManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: CatalogManifest
        do {
            manifest = try decoder.decode(CatalogManifest.self, from: data)
        } catch {
            throw CatalogError.invalidManifest(String(describing: error))
        }
        try manifest.validate()
        return manifest
    }

    private func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw CatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        for (name, entry) in [("taxonomy", taxonomy), ("recipes", recipes)] {
            guard entry.path.range(of: "^\(name)\\.[0-9a-f]{8}\\.json$", options: .regularExpression) != nil else {
                throw CatalogError.invalidManifest("unexpected \(name) path \(entry.path)")
            }
            guard entry.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw CatalogError.invalidManifest("malformed \(name) sha256")
            }
            guard (0...Self.maxFileBytes).contains(entry.bytes) else {
                throw CatalogError.fileTooLarge(entry.path, entry.bytes)
            }
        }
    }
}
```

`Sources/NorseMixologyCore/Catalog/CatalogMeta.swift`:

```swift
import CryptoKit
import Foundation

public enum CatalogSource: String, Sendable {
    case bundled, remote
}

/// What the live catalog database says about itself (`catalog_meta`).
public struct CatalogMeta: Equatable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let generatedAt: Date
    public let source: CatalogSource
    /// The manifest response's ETag, for `If-None-Match`. Remote catalogs only.
    public let etag: String?

    public init(schemaVersion: Int, contentVersion: String, generatedAt: Date, source: CatalogSource, etag: String?) {
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.generatedAt = generatedAt
        self.source = source
        self.etag = etag
    }
}

/// A fully loaded catalog — everything `TaxonomyStore` needs.
public struct LoadedCatalog: Equatable, Sendable {
    public let meta: CatalogMeta
    public let categories: [IngredientCategory]
    public let recipes: [Recipe]

    public init(meta: CatalogMeta, categories: [IngredientCategory], recipes: [Recipe]) {
        self.meta = meta
        self.categories = categories
        self.recipes = recipes
    }
}

/// Whole-second ISO-8601 UTC, the format manifests and `catalog_meta` use.
enum CatalogDate {
    static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func parse(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}

enum CatalogHash {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CatalogManifestTests`
Expected: 9 tests PASS. If `testDateFormatIsWholeSecondUTC` fails on the literal, print `CatalogDate.format(CatalogFixtures.t0)` and correct **the test's expected string only** (the constant is an arbitrary whole-second instant).

- [ ] **Step 6: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Catalog \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogFixtures.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogManifestTests.swift
git commit -m "iOS: catalog manifest model with strict validation"
```

---

### Task 3: Catalog paths and the importer (the only writer)

**Files:**
- Create: `Sources/NorseMixologyCore/Catalog/CatalogPaths.swift`, `Sources/NorseMixologyCore/Catalog/CatalogImporter.swift`
- Modify: `Tests/NorseMixologyCoreTests/CatalogFixtures.swift` (add `tempPaths()` from Task 2 Step 1)
- Test: `Tests/NorseMixologyCoreTests/CatalogImporterTests.swift`

**Interfaces:**
- Consumes: `CatalogError`, `CatalogSchema`, `CatalogManifest`, `CatalogMeta`, `CatalogSource`, `CatalogDate`, `CatalogHash`, `IngredientTaxonomy.loadCategories(from:)`, `IngredientTaxonomy.loadRecipesReportingSkipped(from:)`.
- Produces:
  - `public struct CatalogPaths: Sendable` — `public init(directory: URL)`, `public let directory: URL`, `public var live: URL`, `public var staging: URL`, `public static func applicationSupport() throws -> CatalogPaths`, `public func prepareDirectory() throws`, `public func removeStaging()`, `public func promoteStaging() throws`, `static func removeDatabaseFiles(at: URL)`.
  - `public enum CatalogImporter` — `public static func build(at destination: URL, manifest: CatalogManifest, taxonomyData: Data, recipesData: Data, source: CatalogSource, etag: String?) throws`. On any failure it throws a `CatalogError` and leaves no file at `destination`.

- [ ] **Step 1: Add `tempPaths()` to `CatalogFixtures`** (text in Task 2 Step 1).

- [ ] **Step 2: Write the failing importer tests**

`Tests/NorseMixologyCoreTests/CatalogImporterTests.swift`:

```swift
import XCTest
import GRDB
@testable import NorseMixologyCore

final class CatalogImporterTests: XCTestCase {
    private var paths: CatalogPaths!

    override func setUpWithError() throws {
        paths = try CatalogFixtures.tempPaths()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.directory)
    }

    private func build(taxonomy: Data? = nil, recipes: Data? = nil, manifestFor: (taxonomy: Data, recipes: Data)? = nil) throws {
        let taxonomy = try taxonomy ?? CatalogFixtures.taxonomyData()
        let recipes = try recipes ?? CatalogFixtures.recipesData()
        let hashed = manifestFor ?? (taxonomy, recipes)
        try CatalogImporter.build(
            at: paths.staging,
            manifest: CatalogFixtures.manifest(taxonomy: hashed.taxonomy, recipes: hashed.recipes),
            taxonomyData: taxonomy,
            recipesData: recipes,
            source: .bundled,
            etag: nil
        )
    }

    private func assertNoStagingFile(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path), "failed import left a file", file: file, line: line)
    }

    func testBuildsADatabaseWithEveryRowAndMeta() throws {
        try build()
        let queue = try DatabaseQueue(path: paths.staging.path)
        defer { try? queue.close() }
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), CatalogSchema.version)
            XCTAssertGreaterThanOrEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM style") ?? 0, 60)
            XCTAssertGreaterThanOrEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recipe") ?? 0, 150)
            let meta = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT key, value FROM catalog_meta")
                .map { ($0["key"] as String, $0["value"] as String) })
            XCTAssertEqual(meta["contentVersion"], "aaaaaaaa")
            XCTAssertEqual(meta["source"], "bundled")
            XCTAssertEqual(meta["generatedAt"], CatalogDate.format(CatalogFixtures.t0))
            XCTAssertNil(meta["etag"])
        }
    }

    func testReplacesAnExistingFileAtTheDestination() throws {
        try Data("garbage".utf8).write(to: paths.staging)
        try build()
        let queue = try DatabaseQueue(path: paths.staging.path)
        defer { try? queue.close() }
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }, CatalogSchema.version)
    }

    func testHashMismatchIsRejected() throws {
        let taxonomy = try CatalogFixtures.taxonomyData()
        let recipes = try CatalogFixtures.recipesData()
        XCTAssertThrowsError(try build(taxonomy: taxonomy + Data(" ".utf8), recipes: recipes, manifestFor: (taxonomy, recipes))) { error in
            XCTAssertEqual(error as? CatalogError, .hashMismatch("taxonomy"))
        }
        assertNoStagingFile()
    }

    func testAnySkippedRecipeRejectsTheWholeCatalog() throws {
        let recipes = try CatalogFixtures.recipesData { $0[0]["glassType"] = "bucket" }
        XCTAssertThrowsError(try build(recipes: recipes)) { error in
            guard case CatalogError.malformedRecipes = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testTaxonomyThatIsNotJSONIsRejected() throws {
        XCTAssertThrowsError(try build(taxonomy: Data("<html>".utf8))) { error in
            guard case CatalogError.malformedTaxonomy = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testFamilyNestedUnderTheWrongCategoryIsRejected() throws {
        let taxonomy = try CatalogFixtures.taxonomyData { categories in
            var families = categories[0]["families"] as! [[String: Any]]
            families[0]["categoryId"] = UUID().uuidString
            categories[0]["families"] = families
        }
        XCTAssertThrowsError(try build(taxonomy: taxonomy)) { error in
            guard case CatalogError.invalidStructure = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testFlavourOutOfRangeIsAConstraintViolation() throws {
        let recipes = try CatalogFixtures.recipesData { recipes in
            var profile = recipes[0]["flavorProfile"] as! [String: Any]
            profile["citrus"] = 1.5
            recipes[0]["flavorProfile"] = profile
        }
        XCTAssertThrowsError(try build(recipes: recipes)) { error in
            guard case CatalogError.constraintViolation = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testDanglingStyleReferenceIsAConstraintViolation() throws {
        let recipes = try CatalogFixtures.recipesData { recipes in
            var ingredients = recipes[0]["ingredients"] as! [[String: Any]]
            ingredients[0]["ingredientStyleId"] = UUID().uuidString
            recipes[0]["ingredients"] = ingredients
        }
        XCTAssertThrowsError(try build(recipes: recipes)) { error in
            guard case CatalogError.constraintViolation = error else { return XCTFail("got \(error)") }
        }
        assertNoStagingFile()
    }

    func testPromoteMovesStagingToLiveAndReplacesAnExistingLive() throws {
        try build()
        try paths.promoteStaging()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.live.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path))
        try build()
        try paths.promoteStaging()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path))
    }

    func testRemoveStagingDeletesLeftovers() throws {
        try Data("partial".utf8).write(to: paths.staging)
        try Data("journal".utf8).write(to: URL(fileURLWithPath: paths.staging.path + "-journal"))
        paths.removeStaging()
        assertNoStagingFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path + "-journal"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter CatalogImporterTests`
Expected: compile error — `cannot find 'CatalogPaths' in scope` / `cannot find 'CatalogImporter' in scope`.

- [ ] **Step 4: Implement `CatalogPaths`**

`Sources/NorseMixologyCore/Catalog/CatalogPaths.swift`:

```swift
import Foundation

/// Where the catalog database lives, and the two file operations that make
/// updates atomic: throw away a half-built staging file, and swap a finished
/// one into place in a single rename.
public struct CatalogPaths: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func applicationSupport() throws -> CatalogPaths {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return CatalogPaths(directory: base.appending(path: "Catalog", directoryHint: .isDirectory))
    }

    public var live: URL { directory.appending(path: "catalog.sqlite") }
    public var staging: URL { directory.appending(path: "catalog.new.sqlite") }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func removeStaging() {
        Self.removeDatabaseFiles(at: staging)
    }

    /// Atomically replaces `live` with `staging`. If this throws, `live` is untouched.
    public func promoteStaging() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: live.path) {
            _ = try fileManager.replaceItemAt(live, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: live)
        }
    }

    /// Removes a database file and any SQLite sidecar files next to it.
    static func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
```

- [ ] **Step 5: Implement `CatalogImporter`**

`Sources/NorseMixologyCore/Catalog/CatalogImporter.swift`:

```swift
import Foundation
import GRDB

/// The only code that writes a catalog database. Turns verified JSON bytes
/// into a complete SQLite file at `destination`, or throws and leaves nothing
/// behind — callers never see a half-built catalog.
public enum CatalogImporter {
    public static func build(
        at destination: URL,
        manifest: CatalogManifest,
        taxonomyData: Data,
        recipesData: Data,
        source: CatalogSource,
        etag: String?
    ) throws {
        do {
            try verify(taxonomyData, against: manifest.taxonomy, name: "taxonomy")
            try verify(recipesData, against: manifest.recipes, name: "recipes")
            let categories = try decodeCategories(taxonomyData)
            let recipes = try decodeRecipes(recipesData)
            try checkNesting(categories)
            let meta = CatalogMeta(
                schemaVersion: manifest.schemaVersion,
                contentVersion: manifest.contentVersion,
                generatedAt: manifest.generatedAt,
                source: source,
                etag: etag
            )
            CatalogPaths.removeDatabaseFiles(at: destination)
            try write(categories: categories, recipes: recipes, meta: meta, to: destination)
        } catch {
            CatalogPaths.removeDatabaseFiles(at: destination)
            throw error
        }
    }

    // MARK: - Checks before touching the disk

    private static func verify(_ data: Data, against entry: CatalogManifest.FileEntry, name: String) throws {
        guard data.count <= CatalogManifest.maxFileBytes else {
            throw CatalogError.fileTooLarge(name, data.count)
        }
        guard CatalogHash.sha256Hex(data) == entry.sha256 else {
            throw CatalogError.hashMismatch(name)
        }
    }

    private static func decodeCategories(_ data: Data) throws -> [IngredientCategory] {
        do {
            return try IngredientTaxonomy.loadCategories(from: data)
        } catch {
            throw CatalogError.malformedTaxonomy(String(describing: error))
        }
    }

    /// Stricter than the app's tolerant loader: a remote update with even one
    /// undecodable recipe is rejected whole, and the current catalog is kept.
    private static func decodeRecipes(_ data: Data) throws -> [Recipe] {
        let result: (recipes: [Recipe], skippedCount: Int)
        do {
            result = try IngredientTaxonomy.loadRecipesReportingSkipped(from: data)
        } catch {
            throw CatalogError.malformedRecipes(String(describing: error))
        }
        guard result.skippedCount == 0 else {
            throw CatalogError.malformedRecipes("\(result.skippedCount) recipe(s) could not be decoded")
        }
        return result.recipes
    }

    private static func checkNesting(_ categories: [IngredientCategory]) throws {
        for category in categories {
            for family in category.families {
                guard family.categoryId == category.id else {
                    throw CatalogError.invalidStructure("family \(family.name) is nested under the wrong category")
                }
                for style in family.styles where style.familyId != family.id || style.categoryId != category.id {
                    throw CatalogError.invalidStructure("style \(style.name) is nested under the wrong family or category")
                }
            }
        }
    }

    // MARK: - Writing

    private static func write(categories: [IngredientCategory], recipes: [Recipe], meta: CatalogMeta, to destination: URL) throws {
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: destination.path)
        } catch {
            throw CatalogError.fileSystem(String(describing: error))
        }
        do {
            try queue.write { db in
                try CatalogSchema.create(in: db)
                try insert(meta: meta, into: db)
                try insert(categories: categories, into: db)
                try insert(recipes: recipes, into: db)
            }
            let violations = try queue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }
            guard violations.isEmpty else {
                throw CatalogError.constraintViolation("\(violations.count) foreign key violation(s)")
            }
            let integrity = try queue.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
            guard integrity == "ok" else {
                throw CatalogError.constraintViolation("integrity_check: \(integrity ?? "no result")")
            }
            try queue.close()
        } catch let error as CatalogError {
            try? queue.close()
            throw error
        } catch let error as DatabaseError {
            try? queue.close()
            throw CatalogError.constraintViolation(error.message ?? error.description)
        } catch {
            try? queue.close()
            throw CatalogError.fileSystem(String(describing: error))
        }
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func insert(meta: CatalogMeta, into db: Database) throws {
        var rows: [(String, String)] = [
            ("schemaVersion", String(meta.schemaVersion)),
            ("contentVersion", meta.contentVersion),
            ("generatedAt", CatalogDate.format(meta.generatedAt)),
            ("source", meta.source.rawValue)
        ]
        if let etag = meta.etag {
            rows.append(("etag", etag))
        }
        for (key, value) in rows {
            try db.execute(sql: "INSERT INTO catalog_meta (key, value) VALUES (?, ?)", arguments: [key, value])
        }
    }

    private static func insert(categories: [IngredientCategory], into db: Database) throws {
        let styleColumns = ["id", "family_id", "category_id", "name", "sort_order", "abv_min", "abv_max"] + CatalogSchema.profileColumns
        let styleSQL = "INSERT INTO style (\(styleColumns.joined(separator: ", "))) VALUES (\(placeholders(styleColumns.count)))"
        var familyOrder = 0
        var styleOrder = 0
        for (categoryOrder, category) in categories.enumerated() {
            try db.execute(
                sql: "INSERT INTO category (id, name, sort_order) VALUES (?, ?, ?)",
                arguments: [category.id.uuidString, category.name, categoryOrder]
            )
            for family in category.families {
                try db.execute(
                    sql: "INSERT INTO family (id, category_id, name, sort_order) VALUES (?, ?, ?, ?)",
                    arguments: [family.id.uuidString, category.id.uuidString, family.name, familyOrder]
                )
                familyOrder += 1
                for style in family.styles {
                    var args: [(any DatabaseValueConvertible)?] = [
                        style.id.uuidString, family.id.uuidString, category.id.uuidString,
                        style.name, styleOrder, style.abvMin, style.abvMax
                    ]
                    args.append(contentsOf: CatalogSchema.profileValues(style.flavorProfile).map { $0 as (any DatabaseValueConvertible)? })
                    try db.execute(sql: styleSQL, arguments: StatementArguments(args))
                    styleOrder += 1
                    for (position, brand) in style.exampleBrands.enumerated() {
                        try db.execute(
                            sql: "INSERT INTO style_brand (style_id, position, brand) VALUES (?, ?, ?)",
                            arguments: [style.id.uuidString, position, brand]
                        )
                    }
                }
            }
        }
    }

    private static func insert(recipes: [Recipe], into db: Database) throws {
        let recipeColumns = ["id", "sort_order", "name", "description", "glass_type", "method", "difficulty", "image_url"] + CatalogSchema.profileColumns
        let recipeSQL = "INSERT INTO recipe (\(recipeColumns.joined(separator: ", "))) VALUES (\(placeholders(recipeColumns.count)))"
        for (order, recipe) in recipes.enumerated() {
            var args: [(any DatabaseValueConvertible)?] = [
                recipe.id.uuidString, order, recipe.name, recipe.description,
                recipe.glassType.rawValue, recipe.method.rawValue, recipe.difficulty.rawValue, recipe.imageURL
            ]
            args.append(contentsOf: CatalogSchema.profileValues(recipe.flavorProfile).map { $0 as (any DatabaseValueConvertible)? })
            try db.execute(sql: recipeSQL, arguments: StatementArguments(args))

            for (position, ingredient) in recipe.ingredients.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO recipe_ingredient (recipe_id, position, style_id, amount, preparation, is_optional, substitute_notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [recipe.id.uuidString, position, ingredient.ingredientStyleId.uuidString, ingredient.amount,
                                ingredient.preparation, ingredient.isOptional ? 1 : 0, ingredient.substituteNotes]
                )
            }
            for (position, step) in recipe.steps.enumerated() {
                try db.execute(
                    sql: "INSERT INTO recipe_step (recipe_id, position, text) VALUES (?, ?, ?)",
                    arguments: [recipe.id.uuidString, position, step]
                )
            }
            for (position, tag) in recipe.tags.enumerated() {
                try db.execute(
                    sql: "INSERT INTO recipe_tag (recipe_id, position, tag) VALUES (?, ?, ?)",
                    arguments: [recipe.id.uuidString, position, tag]
                )
            }
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter CatalogImporterTests`
Expected: 10 tests PASS. Then `swift test` — all green.

- [ ] **Step 7: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Catalog \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogFixtures.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogImporterTests.swift
git commit -m "iOS: catalog importer — verified, all-or-nothing SQLite build"
```

---

### Task 4: Read-only catalog loader with round-trip guarantee

**Files:**
- Create: `Sources/NorseMixologyCore/Catalog/CatalogDatabase.swift`
- Test: `Tests/NorseMixologyCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Consumes: `CatalogImporter.build`, `CatalogPaths`, `CatalogSchema.version`, `CatalogDate.parse`, model types.
- Produces: `public enum CatalogDatabase` — `public static func load(from url: URL) throws -> LoadedCatalog`. Opens read-only, checks `user_version`, loads everything, closes. Throws `CatalogError.missingDatabase`, `.schemaMismatch(found:)`, or `.corruptDatabase(String)`; never crashes on a bad file.

- [ ] **Step 1: Write the failing tests**

`Tests/NorseMixologyCoreTests/CatalogDatabaseTests.swift`:

```swift
import XCTest
import GRDB
@testable import NorseMixologyCore

final class CatalogDatabaseTests: XCTestCase {
    private var paths: CatalogPaths!

    override func setUpWithError() throws {
        paths = try CatalogFixtures.tempPaths()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.directory)
    }

    private func buildLive(source: CatalogSource = .bundled, etag: String? = nil) throws {
        let taxonomy = try CatalogFixtures.taxonomyData()
        let recipes = try CatalogFixtures.recipesData()
        try CatalogImporter.build(at: paths.staging, manifest: CatalogFixtures.manifest(taxonomy: taxonomy, recipes: recipes),
                                  taxonomyData: taxonomy, recipesData: recipes, source: source, etag: etag)
        try paths.promoteStaging()
    }

    func testRoundTripEqualsTheJSONLoaders() throws {
        try buildLive()
        let loaded = try CatalogDatabase.load(from: paths.live)
        XCTAssertEqual(loaded.categories, try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        XCTAssertEqual(loaded.recipes, try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData()))
    }

    func testMetaRoundTrips() throws {
        try buildLive(source: .remote, etag: "\"abc\"")
        let meta = try CatalogDatabase.load(from: paths.live).meta
        XCTAssertEqual(meta, CatalogMeta(schemaVersion: 1, contentVersion: "aaaaaaaa", generatedAt: CatalogFixtures.t0, source: .remote, etag: "\"abc\""))
    }

    func testMissingFileThrowsMissingDatabase() {
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live)) { error in
            XCTAssertEqual(error as? CatalogError, .missingDatabase)
        }
    }

    func testWrongUserVersionThrowsSchemaMismatch() throws {
        try buildLive()
        let queue = try DatabaseQueue(path: paths.live.path)
        try queue.writeWithoutTransaction { try $0.execute(sql: "PRAGMA user_version = 0") }
        try queue.close()
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live)) { error in
            XCTAssertEqual(error as? CatalogError, .schemaMismatch(found: 0))
        }
    }

    func testGarbageFileThrowsCorruptDatabase() throws {
        try Data(repeating: 0x42, count: 4096).write(to: paths.live)
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live)) { error in
            guard case CatalogError.corruptDatabase = error else { return XCTFail("got \(error)") }
        }
    }

    func testTruncatedFileThrowsInsteadOfCrashing() throws {
        try buildLive()
        let handle = try FileHandle(forWritingTo: paths.live)
        try handle.truncate(atOffset: 8192)
        try handle.close()
        XCTAssertThrowsError(try CatalogDatabase.load(from: paths.live))
    }

    func testLoadingDoesNotModifyTheFile() throws {
        try buildLive()
        let before = try Data(contentsOf: paths.live)
        _ = try CatalogDatabase.load(from: paths.live)
        XCTAssertEqual(try Data(contentsOf: paths.live), before)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CatalogDatabaseTests`
Expected: compile error — `cannot find 'CatalogDatabase' in scope`.

- [ ] **Step 3: Implement the loader**

`Sources/NorseMixologyCore/Catalog/CatalogDatabase.swift`:

```swift
import Foundation
import GRDB

/// Reads a catalog database back into the app's model types. Read-only, and
/// every failure is a thrown `CatalogError` — rows are decoded with throwing
/// `Decodable` records rather than force-typed subscripts, so a damaged file
/// can never crash the app at launch.
public enum CatalogDatabase {
    public static func load(from url: URL) throws -> LoadedCatalog {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CatalogError.missingDatabase
        }
        var configuration = Configuration()
        configuration.readonly = true
        do {
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            defer { try? queue.close() }
            return try queue.read { db in
                let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
                guard version == CatalogSchema.version else {
                    throw CatalogError.schemaMismatch(found: version)
                }
                return LoadedCatalog(meta: try readMeta(db), categories: try readCategories(db), recipes: try readRecipes(db))
            }
        } catch let error as CatalogError {
            throw error
        } catch {
            throw CatalogError.corruptDatabase(String(describing: error))
        }
    }

    // MARK: - Rows

    private struct MetaRow: SnakeCaseRecord { let key: String; let value: String }
    private struct CategoryRow: SnakeCaseRecord { let id: String; let name: String }
    private struct FamilyRow: SnakeCaseRecord { let id: String; let categoryId: String; let name: String }
    private struct StyleRow: SnakeCaseRecord {
        let id: String, familyId: String, categoryId: String, name: String, abvMin: Double, abvMax: Double
        let sweetness: Double, bitterness: Double, smokiness: Double, citrus: Double, floral: Double
        let spice: Double, herbal: Double, fruity: Double, oaky: Double, abv: Double
    }
    private struct BrandRow: SnakeCaseRecord { let styleId: String; let brand: String }
    private struct RecipeRow: SnakeCaseRecord {
        let id: String, name: String, description: String, glassType: String, method: String, difficulty: String, imageUrl: String?
        let sweetness: Double, bitterness: Double, smokiness: Double, citrus: Double, floral: Double
        let spice: Double, herbal: Double, fruity: Double, oaky: Double, abv: Double
    }
    private struct IngredientRow: SnakeCaseRecord {
        let recipeId: String, styleId: String, amount: String, preparation: String?, isOptional: Int, substituteNotes: String?
    }
    private struct StepRow: SnakeCaseRecord { let recipeId: String; let text: String }
    private struct TagRow: SnakeCaseRecord { let recipeId: String; let tag: String }

    // MARK: - Readers

    private static func readMeta(_ db: Database) throws -> CatalogMeta {
        let rows = try MetaRow.fetchAll(db, sql: "SELECT key, value FROM catalog_meta")
        let values = Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        guard
            let schemaVersion = values["schemaVersion"].flatMap(Int.init),
            let contentVersion = values["contentVersion"],
            let generatedAt = values["generatedAt"].flatMap(CatalogDate.parse),
            let source = values["source"].flatMap(CatalogSource.init(rawValue:))
        else {
            throw CatalogError.corruptDatabase("catalog_meta is incomplete")
        }
        return CatalogMeta(schemaVersion: schemaVersion, contentVersion: contentVersion, generatedAt: generatedAt, source: source, etag: values["etag"])
    }

    private static func readCategories(_ db: Database) throws -> [IngredientCategory] {
        let categoryRows = try CategoryRow.fetchAll(db, sql: "SELECT id, name FROM category ORDER BY sort_order")
        let familyRows = try FamilyRow.fetchAll(db, sql: "SELECT id, category_id, name FROM family ORDER BY sort_order")
        let styleColumns = (["id", "family_id", "category_id", "name", "abv_min", "abv_max"] + CatalogSchema.profileColumns).joined(separator: ", ")
        let styleRows = try StyleRow.fetchAll(db, sql: "SELECT \(styleColumns) FROM style ORDER BY sort_order")
        let brandRows = try BrandRow.fetchAll(db, sql: "SELECT style_id, brand FROM style_brand ORDER BY style_id, position")

        var brandsByStyle: [String: [String]] = [:]
        for row in brandRows { brandsByStyle[row.styleId, default: []].append(row.brand) }

        var stylesByFamily: [String: [IngredientStyle]] = [:]
        for row in styleRows {
            let style = IngredientStyle(
                id: try uuid(row.id), name: row.name, familyId: try uuid(row.familyId), categoryId: try uuid(row.categoryId),
                exampleBrands: brandsByStyle[row.id] ?? [],
                flavorProfile: FlavorProfile(sweetness: row.sweetness, bitterness: row.bitterness, smokiness: row.smokiness,
                                             citrus: row.citrus, floral: row.floral, spice: row.spice, herbal: row.herbal,
                                             fruity: row.fruity, oaky: row.oaky, abv: row.abv),
                abvMin: row.abvMin, abvMax: row.abvMax
            )
            stylesByFamily[row.familyId, default: []].append(style)
        }

        var familiesByCategory: [String: [IngredientFamily]] = [:]
        for row in familyRows {
            let family = IngredientFamily(id: try uuid(row.id), name: row.name, categoryId: try uuid(row.categoryId),
                                          styles: stylesByFamily[row.id] ?? [])
            familiesByCategory[row.categoryId, default: []].append(family)
        }

        return try categoryRows.map { row in
            IngredientCategory(id: try uuid(row.id), name: row.name, families: familiesByCategory[row.id] ?? [])
        }
    }

    private static func readRecipes(_ db: Database) throws -> [Recipe] {
        let recipeColumns = (["id", "name", "description", "glass_type", "method", "difficulty", "image_url"] + CatalogSchema.profileColumns).joined(separator: ", ")
        let recipeRows = try RecipeRow.fetchAll(db, sql: "SELECT \(recipeColumns) FROM recipe ORDER BY sort_order")
        let ingredientRows = try IngredientRow.fetchAll(db, sql: """
            SELECT recipe_id, style_id, amount, preparation, is_optional, substitute_notes
            FROM recipe_ingredient ORDER BY recipe_id, position
            """)
        let stepRows = try StepRow.fetchAll(db, sql: "SELECT recipe_id, text FROM recipe_step ORDER BY recipe_id, position")
        let tagRows = try TagRow.fetchAll(db, sql: "SELECT recipe_id, tag FROM recipe_tag ORDER BY recipe_id, position")

        var ingredients: [String: [RecipeIngredient]] = [:]
        for row in ingredientRows {
            ingredients[row.recipeId, default: []].append(RecipeIngredient(
                ingredientStyleId: try uuid(row.styleId), amount: row.amount, preparation: row.preparation,
                isOptional: row.isOptional != 0, substituteNotes: row.substituteNotes
            ))
        }
        var steps: [String: [String]] = [:]
        for row in stepRows { steps[row.recipeId, default: []].append(row.text) }
        var tags: [String: [String]] = [:]
        for row in tagRows { tags[row.recipeId, default: []].append(row.tag) }

        return try recipeRows.map { row in
            guard
                let glassType = GlassType(rawValue: row.glassType),
                let method = Method(rawValue: row.method),
                let difficulty = Difficulty(rawValue: row.difficulty)
            else {
                throw CatalogError.corruptDatabase("recipe \(row.id) has an unknown glass type, method or difficulty")
            }
            return Recipe(
                id: try uuid(row.id), name: row.name, description: row.description, glassType: glassType, method: method,
                ingredients: ingredients[row.id] ?? [], steps: steps[row.id] ?? [],
                flavorProfile: FlavorProfile(sweetness: row.sweetness, bitterness: row.bitterness, smokiness: row.smokiness,
                                             citrus: row.citrus, floral: row.floral, spice: row.spice, herbal: row.herbal,
                                             fruity: row.fruity, oaky: row.oaky, abv: row.abv),
                tags: tags[row.id] ?? [], difficulty: difficulty, imageURL: row.imageUrl
            )
        }
    }

    private static func uuid(_ string: String) throws -> UUID {
        guard let value = UUID(uuidString: string) else {
            throw CatalogError.corruptDatabase("invalid UUID \(string)")
        }
        return value
    }
}

/// Row records decode columns like `abv_min` / `image_url` into `abvMin` / `imageUrl`.
private protocol SnakeCaseRecord: Decodable, FetchableRecord {}

extension SnakeCaseRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
```

The row structs are nested in `CatalogDatabase` and conform to the file-private `SnakeCaseRecord` protocol declared at file scope below it; its extension overrides GRDB's default column decoding strategy for exactly these types. `.convertFromSnakeCase` maps `image_url` → `imageUrl` (hence that property's name).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CatalogDatabaseTests`
Expected: 7 tests PASS. `testRoundTripEqualsTheJSONLoaders` is the key one — if it fails, compare the first differing element; ordering bugs show up here (every child table is read `ORDER BY ..., position`).

- [ ] **Step 5: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Catalog/CatalogDatabase.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogDatabaseTests.swift
git commit -m "iOS: read-only catalog loader with JSON round-trip guarantee"
```

---

### Task 5: Launch bootstrap

**Files:**
- Create: `Sources/NorseMixologyCore/Catalog/CatalogBootstrap.swift`
- Modify: `Tests/NorseMixologyCoreTests/CatalogFixtures.swift` (add `installLive` from Task 2 Step 1)
- Test: `Tests/NorseMixologyCoreTests/CatalogBootstrapTests.swift`

**Interfaces:**
- Consumes: `CatalogPaths`, `CatalogImporter.build`, `CatalogDatabase.load`, `CatalogManifest.decode`, `AppLog.catalog`.
- Produces:
  - `public struct BundledCatalog: Sendable` — `manifestData: Data`, `taxonomyData: Data`, `recipesData: Data`, memberwise `public init`. Empty `Data` means "not in the bundle" and is treated as an unusable bundled catalog.
  - `public enum CatalogBootstrapResult: Equatable, Sendable { case loaded(LoadedCatalog); case unavailable(reason: String) }`.
  - `public enum CatalogBootstrap { public static func run(paths: CatalogPaths, bundled: BundledCatalog) -> CatalogBootstrapResult }`.

Decision rules (spec §5 Launch; rows 11, 13, 14, 15, 17):
1. Create the directory; delete staging leftovers.
2. Load live. Keep it if it loads and the bundled manifest is unusable or not newer (`bundled.generatedAt <= live.generatedAt`).
3. Otherwise rebuild from bundled → staging → promote → load.
4. If the rebuild fails: return the older live catalog if one loaded, else `.unavailable`.

- [ ] **Step 1: Add `installLive` to `CatalogFixtures`** (text in Task 2 Step 1).

- [ ] **Step 2: Write the failing tests**

`Tests/NorseMixologyCoreTests/CatalogBootstrapTests.swift`:

```swift
import XCTest
import GRDB
@testable import NorseMixologyCore

final class CatalogBootstrapTests: XCTestCase {
    private var paths: CatalogPaths!

    override func setUpWithError() throws {
        paths = try CatalogFixtures.tempPaths()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.directory)
    }

    private func bundled(generatedAt: Date = CatalogFixtures.t0, contentVersion: String = "bbbbbbbb", recipes: Data? = nil) throws -> BundledCatalog {
        let taxonomy = try CatalogFixtures.taxonomyData()
        let recipesData = try recipes ?? CatalogFixtures.recipesData()
        let manifest = CatalogFixtures.manifest(taxonomy: taxonomy, recipes: recipesData, generatedAt: generatedAt, contentVersion: contentVersion)
        return BundledCatalog(manifestData: try CatalogFixtures.encode(manifest), taxonomyData: taxonomy, recipesData: recipesData)
    }

    private func loaded(_ result: CatalogBootstrapResult, file: StaticString = #filePath, line: UInt = #line) throws -> LoadedCatalog {
        guard case .loaded(let catalog) = result else {
            XCTFail("expected .loaded, got \(result)", file: file, line: line)
            throw CatalogError.missingDatabase
        }
        return catalog
    }

    func testFirstLaunchBuildsFromTheBundledCatalog() throws {
        let catalog = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled()))
        XCTAssertEqual(catalog.meta.source, .bundled)
        XCTAssertEqual(catalog.meta.contentVersion, "bbbbbbbb")
        XCTAssertGreaterThanOrEqual(catalog.recipes.count, 150)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.live.path))
    }

    func testSecondLaunchReusesTheLiveCatalogWithoutRebuilding() throws {
        _ = CatalogBootstrap.run(paths: paths, bundled: try bundled())
        let modified = try FileManager.default.attributesOfItem(atPath: paths.live.path)[.modificationDate] as? Date
        let catalog = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled()))
        XCTAssertEqual(catalog.meta.contentVersion, "bbbbbbbb")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: paths.live.path)[.modificationDate] as? Date, modified)
    }

    // Row 11
    func testLeftoverStagingFileIsRemoved() throws {
        try Data("half-written".utf8).write(to: paths.staging)
        _ = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path))
    }

    // Row 13
    func testCorruptLiveCatalogIsRebuiltFromBundled() throws {
        try Data(repeating: 0x42, count: 4096).write(to: paths.live)
        let catalog = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled()))
        XCTAssertEqual(catalog.meta.source, .bundled)
    }

    // Row 14
    func testSchemaMismatchIsRebuiltFromBundled() throws {
        try CatalogFixtures.installLive(at: paths, generatedAt: CatalogFixtures.t0.addingTimeInterval(3600), source: .remote)
        let queue = try DatabaseQueue(path: paths.live.path)
        try queue.writeWithoutTransaction { try $0.execute(sql: "PRAGMA user_version = 0") }
        try queue.close()
        let catalog = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled()))
        XCTAssertEqual(catalog.meta.source, .bundled)
    }

    // Row 15 — bundled newer wins
    func testNewerBundledCatalogReplacesAnOlderLiveOne() throws {
        try CatalogFixtures.installLive(at: paths, generatedAt: CatalogFixtures.t0, contentVersion: "aaaaaaaa", source: .remote)
        let catalog = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled(generatedAt: CatalogFixtures.t0.addingTimeInterval(3600))))
        XCTAssertEqual(catalog.meta.contentVersion, "bbbbbbbb")
        XCTAssertEqual(catalog.meta.source, .bundled)
    }

    // Row 15 — remote newer is kept
    func testNewerLiveCatalogIsKept() throws {
        try CatalogFixtures.installLive(at: paths, generatedAt: CatalogFixtures.t0.addingTimeInterval(3600), contentVersion: "aaaaaaaa", source: .remote, etag: "\"x\"")
        let catalog = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled(generatedAt: CatalogFixtures.t0)))
        XCTAssertEqual(catalog.meta.contentVersion, "aaaaaaaa")
        XCTAssertEqual(catalog.meta.source, .remote)
    }

    // Row 17 — nothing usable
    func testCorruptBundledCatalogWithNoLiveOneIsUnavailable() throws {
        var bad = try bundled()
        bad = BundledCatalog(manifestData: bad.manifestData, taxonomyData: bad.taxonomyData, recipesData: Data("garbage".utf8))
        guard case .unavailable = CatalogBootstrap.run(paths: paths, bundled: bad) else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path))
    }

    // Row 17 — an older-but-valid live catalog beats "unavailable"
    func testFailedRebuildFallsBackToTheOlderLiveCatalog() throws {
        try CatalogFixtures.installLive(at: paths, generatedAt: CatalogFixtures.t0, contentVersion: "aaaaaaaa")
        let good = try bundled(generatedAt: CatalogFixtures.t0.addingTimeInterval(3600))
        let bad = BundledCatalog(manifestData: good.manifestData, taxonomyData: good.taxonomyData, recipesData: Data("garbage".utf8))
        let catalog = try loaded(CatalogBootstrap.run(paths: paths, bundled: bad))
        XCTAssertEqual(catalog.meta.contentVersion, "aaaaaaaa")
    }

    func testMissingBundleStillUsesALiveCatalog() throws {
        try CatalogFixtures.installLive(at: paths)
        let empty = BundledCatalog(manifestData: Data(), taxonomyData: Data(), recipesData: Data())
        _ = try loaded(CatalogBootstrap.run(paths: paths, bundled: empty))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter CatalogBootstrapTests`
Expected: compile error — `cannot find 'BundledCatalog' in scope`.

- [ ] **Step 4: Implement the bootstrap**

`Sources/NorseMixologyCore/Catalog/CatalogBootstrap.swift`:

```swift
import Foundation

/// The catalog files shipped inside the app. Empty data means "missing from
/// the bundle" and is handled like any other unusable bundled catalog.
public struct BundledCatalog: Sendable {
    public let manifestData: Data
    public let taxonomyData: Data
    public let recipesData: Data

    public init(manifestData: Data, taxonomyData: Data, recipesData: Data) {
        self.manifestData = manifestData
        self.taxonomyData = taxonomyData
        self.recipesData = recipesData
    }
}

public enum CatalogBootstrapResult: Equatable, Sendable {
    case loaded(LoadedCatalog)
    case unavailable(reason: String)
}

/// Decides, once per launch, which catalog the app runs on. Never throws:
/// every failure falls back to the next-best catalog, and only when there is
/// none at all does it report `.unavailable`.
public enum CatalogBootstrap {
    public static func run(paths: CatalogPaths, bundled: BundledCatalog) -> CatalogBootstrapResult {
        do {
            try paths.prepareDirectory()
        } catch {
            return .unavailable(reason: "Catalog directory unavailable: \(error)")
        }
        paths.removeStaging()

        let usableManifest: CatalogManifest?
        do {
            usableManifest = try CatalogManifest.decode(from: bundled.manifestData)
        } catch {
            AppLog.catalog.error("Bundled catalog manifest unusable: \(String(describing: error), privacy: .public)")
            usableManifest = nil
        }

        var existing: LoadedCatalog?
        do {
            existing = try CatalogDatabase.load(from: paths.live)
        } catch CatalogError.missingDatabase {
            AppLog.catalog.info("No catalog database yet; building from the bundled catalog")
        } catch {
            AppLog.catalog.error("Catalog database unreadable, rebuilding: \(String(describing: error), privacy: .public)")
        }

        if let existing {
            guard let usableManifest, usableManifest.generatedAt > existing.meta.generatedAt else {
                return .loaded(existing)
            }
            AppLog.catalog.info("Bundled catalog is newer than the stored one; rebuilding")
        }

        guard let bundledManifest = usableManifest else {
            return .unavailable(reason: "No readable catalog database and the bundled catalog is unusable")
        }

        do {
            try CatalogImporter.build(
                at: paths.staging,
                manifest: bundledManifest,
                taxonomyData: bundled.taxonomyData,
                recipesData: bundled.recipesData,
                source: .bundled,
                etag: nil
            )
            try paths.promoteStaging()
            return .loaded(try CatalogDatabase.load(from: paths.live))
        } catch {
            paths.removeStaging()
            AppLog.catalog.error("Rebuilding from the bundled catalog failed: \(String(describing: error), privacy: .public)")
            if let existing {
                return .loaded(existing)
            }
            return .unavailable(reason: "Rebuilding from the bundled catalog failed: \(error)")
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CatalogBootstrapTests`
Expected: 10 tests PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Catalog/CatalogBootstrap.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogFixtures.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogBootstrapTests.swift
git commit -m "iOS: catalog launch bootstrap with layered fallbacks"
```

---

### Task 6: Background updater

**Files:**
- Create: `Sources/NorseMixologyCore/Catalog/CatalogUpdater.swift`
- Test: `Tests/NorseMixologyCoreTests/StubURLProtocol.swift`, `Tests/NorseMixologyCoreTests/CatalogUpdaterTests.swift`

**Interfaces:**
- Consumes: `CatalogPaths`, `CatalogManifest`, `CatalogImporter.build`, `CatalogMeta`, `CatalogError`.
- Produces:
  - `public enum CatalogUpdateOutcome: Equatable, Sendable { case notModified, upToDate, updated(contentVersion: String), failed(CatalogError) }`.
  - `public struct CatalogUpdater: Sendable` — `public static let manifestByteLimit = 65_536`; `public init(baseURL: URL, session: URLSession = CatalogUpdater.makeSession(), paths: CatalogPaths, promote: @escaping @Sendable (CatalogPaths) throws -> Void = { try $0.promoteStaging() })`; `public static func makeSession() -> URLSession`; `public func refresh(current: CatalogMeta) async -> CatalogUpdateOutcome` (never throws; on any failure the live catalog is untouched and staging is removed).

- [ ] **Step 1: Write the URL stub**

`Tests/NorseMixologyCoreTests/StubURLProtocol.swift`:

```swift
import Foundation

/// Serves canned responses to a URLSession built with `StubURLProtocol.session()`.
/// Tests run serially within a class, so plain static state is fine here.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var error: Error?
    }

    static var handler: ((URLRequest) -> Response)?
    static var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        requests = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let response = Self.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Write the failing updater tests**

`Tests/NorseMixologyCoreTests/CatalogUpdaterTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

final class CatalogUpdaterTests: XCTestCase {
    private let baseURL = URL(string: "https://catalog.test/norse-catalog/")!
    private var paths: CatalogPaths!
    private var current: CatalogMeta!
    private var remoteTaxonomy: Data!
    private var remoteRecipes: Data!
    private var remoteManifest: CatalogManifest!

    override func setUpWithError() throws {
        StubURLProtocol.reset()
        paths = try CatalogFixtures.tempPaths()
        current = try CatalogFixtures.installLive(at: paths, generatedAt: CatalogFixtures.t0, contentVersion: "aaaaaaaa", source: .remote, etag: "\"old\"")
        remoteTaxonomy = try CatalogFixtures.taxonomyData()
        remoteRecipes = try CatalogFixtures.recipesData { $0[0]["name"] = "Remote Martini" }
        remoteManifest = CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: remoteRecipes,
                                                  generatedAt: CatalogFixtures.t0.addingTimeInterval(3600), contentVersion: "bbbbbbbb")
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: paths.directory)
    }

    // MARK: - Helpers

    private func updater(promote: (@Sendable (CatalogPaths) throws -> Void)? = nil) -> CatalogUpdater {
        if let promote {
            return CatalogUpdater(baseURL: baseURL, session: StubURLProtocol.session(), paths: paths, promote: promote)
        }
        return CatalogUpdater(baseURL: baseURL, session: StubURLProtocol.session(), paths: paths)
    }

    /// Serves `manifest` plus the two remote files; anything else is a 404.
    private func serve(
        manifest: Data? = nil,
        manifestStatus: Int = 200,
        taxonomyBody: Data? = nil,
        recipesBody: Data? = nil
    ) throws {
        let manifestData = try manifest ?? CatalogFixtures.encode(remoteManifest)
        let taxonomyPath = remoteManifest.taxonomy.path
        let recipesPath = remoteManifest.recipes.path
        let taxonomy = taxonomyBody ?? remoteTaxonomy!
        let recipes = recipesBody ?? remoteRecipes!
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/norse-catalog/v1/manifest.json":
                return .init(status: manifestStatus, headers: ["ETag": "\"new\""], body: manifestStatus == 304 ? Data() : manifestData)
            case "/norse-catalog/v1/\(taxonomyPath)":
                return .init(body: taxonomy)
            case "/norse-catalog/v1/\(recipesPath)":
                return .init(body: recipes)
            default:
                return .init(status: 404)
            }
        }
    }

    private func assertLiveUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try CatalogDatabase.load(from: paths.live).meta, current, file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path), "staging left behind", file: file, line: line)
    }

    private func assertFailed(_ outcome: CatalogUpdateOutcome, file: StaticString = #filePath, line: UInt = #line,
                              where matches: (CatalogError) -> Bool) {
        guard case .failed(let error) = outcome, matches(error) else {
            return XCTFail("unexpected outcome \(outcome)", file: file, line: line)
        }
    }

    // MARK: - Happy paths

    func testNewerManifestIsDownloadedImportedAndSwappedIn() async throws {
        try serve()
        let outcome = await updater().refresh(current: current)
        XCTAssertEqual(outcome, .updated(contentVersion: "bbbbbbbb"))
        let live = try CatalogDatabase.load(from: paths.live)
        XCTAssertEqual(live.meta.contentVersion, "bbbbbbbb")
        XCTAssertEqual(live.meta.source, .remote)
        XCTAssertEqual(live.meta.etag, "\"new\"")
        XCTAssertEqual(live.recipes.first?.name, "Remote Martini")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path))
    }

    func testNotModifiedSendsTheStoredETag() async throws {
        try serve(manifestStatus: 304)
        let outcome = await updater().refresh(current: current)
        XCTAssertEqual(outcome, .notModified)
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match"), "\"old\"")
        try assertLiveUnchanged()
    }

    func testSameContentVersionIsUpToDate() async throws {
        remoteManifest = CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: remoteRecipes,
                                                  generatedAt: CatalogFixtures.t0.addingTimeInterval(3600), contentVersion: "aaaaaaaa")
        try serve()
        let outcome = await updater().refresh(current: current)
        XCTAssertEqual(outcome, .upToDate)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "no files should be fetched")
        try assertLiveUnchanged()
    }

    // Row 2 (client side): a CDN-stale manifest must not downgrade the catalog.
    func testOlderManifestIsIgnored() async throws {
        remoteManifest = CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: remoteRecipes,
                                                  generatedAt: CatalogFixtures.t0.addingTimeInterval(-3600), contentVersion: "cccccccc")
        try serve()
        let outcome = await updater().refresh(current: current)
        XCTAssertEqual(outcome, .upToDate)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        try assertLiveUnchanged()
    }

    // MARK: - Row 4: host down / gone

    func testManifest404Fails() async throws {
        StubURLProtocol.handler = { _ in .init(status: 404) }
        assertFailed(await updater().refresh(current: current)) { $0 == .http(status: 404) }
        try assertLiveUnchanged()
    }

    func testServerErrorFails() async throws {
        StubURLProtocol.handler = { _ in .init(status: 503) }
        assertFailed(await updater().refresh(current: current)) { $0 == .http(status: 503) }
        try assertLiveUnchanged()
    }

    func testMissingFileFails() async throws {
        try serve()
        let manifestData = try CatalogFixtures.encode(remoteManifest)
        StubURLProtocol.handler = { request in
            request.url?.lastPathComponent == "manifest.json" ? .init(body: manifestData) : .init(status: 404)
        }
        assertFailed(await updater().refresh(current: current)) { $0 == .http(status: 404) }
        try assertLiveUnchanged()
    }

    // MARK: - Row 6: offline / timeout

    func testOfflineFails() async throws {
        StubURLProtocol.handler = { _ in .init(error: URLError(.notConnectedToInternet)) }
        assertFailed(await updater().refresh(current: current)) { if case .transport = $0 { return true }; return false }
        try assertLiveUnchanged()
    }

    func testTimeoutFails() async throws {
        StubURLProtocol.handler = { _ in .init(error: URLError(.timedOut)) }
        assertFailed(await updater().refresh(current: current)) { if case .transport = $0 { return true }; return false }
        try assertLiveUnchanged()
    }

    func testSessionUsesA15SecondTimeoutAndNoCache() {
        let configuration = CatalogUpdater.makeSession().configuration
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertNil(configuration.urlCache)
    }

    // MARK: - Row 7: captive portal

    func testHTMLManifestFails() async throws {
        try serve(manifest: Data("<html><body>Sign in to Wi-Fi</body></html>".utf8))
        assertFailed(await updater().refresh(current: current)) { if case .invalidManifest = $0 { return true }; return false }
        try assertLiveUnchanged()
    }

    // MARK: - Row 8: oversized

    func testManifestAdvertisingAnOversizedFileFails() async throws {
        let big = CatalogManifest(schemaVersion: 1, contentVersion: "bbbbbbbb", generatedAt: remoteManifest.generatedAt,
                                  taxonomy: .init(path: remoteManifest.taxonomy.path, sha256: remoteManifest.taxonomy.sha256, bytes: 3_000_000),
                                  recipes: remoteManifest.recipes)
        try serve(manifest: CatalogFixtures.encode(big))
        assertFailed(await updater().refresh(current: current)) { if case .fileTooLarge = $0 { return true }; return false }
        try assertLiveUnchanged()
    }

    func testOversizedBodyIsCutOffWhileStreaming() async throws {
        try serve(taxonomyBody: Data(repeating: 0x20, count: CatalogManifest.maxFileBytes + 1))
        assertFailed(await updater().refresh(current: current)) { if case .fileTooLarge = $0 { return true }; return false }
        try assertLiveUnchanged()
    }

    // MARK: - Row 9: mismatched versions

    func testHashMismatchFails() async throws {
        try serve(recipesBody: CatalogFixtures.recipesData())
        assertFailed(await updater().refresh(current: current)) { $0 == .hashMismatch("recipes") }
        try assertLiveUnchanged()
    }

    // MARK: - Row 10: bad content

    func testMalformedRecipeRejectsTheUpdate() async throws {
        remoteRecipes = try CatalogFixtures.recipesData { $0[0]["glassType"] = "bucket" }
        remoteManifest = CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: remoteRecipes,
                                                  generatedAt: CatalogFixtures.t0.addingTimeInterval(3600), contentVersion: "bbbbbbbb")
        try serve()
        assertFailed(await updater().refresh(current: current)) { if case .malformedRecipes = $0 { return true }; return false }
        try assertLiveUnchanged()
    }

    // MARK: - Row 12: swap fails

    func testFailedSwapLeavesTheLiveCatalogUntouched() async throws {
        try serve()
        let outcome = await updater(promote: { _ in throw CocoaError(.fileWriteUnknown) }).refresh(current: current)
        assertFailed(outcome) { if case .fileSystem = $0 { return true }; return false }
        try assertLiveUnchanged()
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter CatalogUpdaterTests`
Expected: compile error — `cannot find 'CatalogUpdater' in scope`.

- [ ] **Step 4: Implement the updater**

`Sources/NorseMixologyCore/Catalog/CatalogUpdater.swift`:

```swift
import Foundation

public enum CatalogUpdateOutcome: Equatable, Sendable {
    case notModified
    case upToDate
    case updated(contentVersion: String)
    case failed(CatalogError)
}

/// Checks the catalog host for a newer manifest and, if there is one, builds
/// it into the staging database and swaps it in for the next launch. Never
/// throws: whatever goes wrong, the live catalog is left exactly as it was.
public struct CatalogUpdater: Sendable {
    public static let manifestByteLimit = 65_536

    private let v1URL: URL
    private let session: URLSession
    private let paths: CatalogPaths
    private let promote: @Sendable (CatalogPaths) throws -> Void

    public init(
        baseURL: URL,
        session: URLSession = CatalogUpdater.makeSession(),
        paths: CatalogPaths,
        promote: @escaping @Sendable (CatalogPaths) throws -> Void = { try $0.promoteStaging() }
    ) {
        self.v1URL = baseURL.appending(path: "v1", directoryHint: .isDirectory)
        self.session = session
        self.paths = paths
        self.promote = promote
    }

    /// Ephemeral with no URL cache: conditional requests are driven by the
    /// ETag stored in `catalog_meta`, not by an HTTP cache that could hand
    /// back a stale body.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func refresh(current: CatalogMeta) async -> CatalogUpdateOutcome {
        do {
            return try await performRefresh(current: current)
        } catch {
            paths.removeStaging()
            if let catalogError = error as? CatalogError {
                return .failed(catalogError)
            }
            return .failed(.transport(String(describing: error)))
        }
    }

    private func performRefresh(current: CatalogMeta) async throws -> CatalogUpdateOutcome {
        var request = URLRequest(url: v1URL.appending(path: "manifest.json"))
        if let etag = current.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (response, manifestData) = try await fetch(request, limit: Self.manifestByteLimit)
        if response.statusCode == 304 {
            return .notModified
        }
        guard response.statusCode == 200 else {
            throw CatalogError.http(status: response.statusCode)
        }
        let manifest = try CatalogManifest.decode(from: manifestData)
        // A CDN edge can still serve an older manifest after we applied a newer one.
        guard manifest.contentVersion != current.contentVersion, manifest.generatedAt > current.generatedAt else {
            return .upToDate
        }

        let taxonomyData = try await fetchFile(manifest.taxonomy)
        let recipesData = try await fetchFile(manifest.recipes)
        try CatalogImporter.build(
            at: paths.staging,
            manifest: manifest,
            taxonomyData: taxonomyData,
            recipesData: recipesData,
            source: .remote,
            etag: response.value(forHTTPHeaderField: "ETag")
        )
        do {
            try promote(paths)
        } catch {
            throw CatalogError.fileSystem(String(describing: error))
        }
        return .updated(contentVersion: manifest.contentVersion)
    }

    private func fetchFile(_ entry: CatalogManifest.FileEntry) async throws -> Data {
        let (response, data) = try await fetch(URLRequest(url: v1URL.appending(path: entry.path)), limit: CatalogManifest.maxFileBytes)
        guard response.statusCode == 200 else {
            throw CatalogError.http(status: response.statusCode)
        }
        return data
    }

    /// Streams the body and stops as soon as it exceeds `limit`, so an
    /// oversized response is never held in memory whole.
    private func fetch(_ request: URLRequest, limit: Int) async throws -> (HTTPURLResponse, Data) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.transport("Not an HTTP response")
        }
        let name = request.url?.lastPathComponent ?? "response"
        if http.expectedContentLength > Int64(limit) {
            throw CatalogError.fileTooLarge(name, Int(http.expectedContentLength))
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                throw CatalogError.fileTooLarge(name, data.count)
            }
        }
        return (http, data)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CatalogUpdaterTests`
Expected: 16 tests PASS. If requests hang with the stub, check that `StubURLProtocol.session()` is the session passed to the updater (the default session bypasses the stub and would hit the network).

- [ ] **Step 6: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Catalog/CatalogUpdater.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/StubURLProtocol.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogUpdaterTests.swift
git commit -m "iOS: background catalog updater with streaming caps and atomic swap"
```

---

### Task 7: Matching tolerates styles that left the catalog (row 16)

Once the catalog can change, a cabinet item can point at a style the new catalog no longer has (a "ghost"). Today the matching engine's family-similarity step would use a ghost as a substitute and resolve it with `substituteStyle: nil`, which makes a recipe look like an **exact** match with no substitution shown. Ghosts must never resolve anything.

**Files:**
- Modify: `Sources/NorseMixologyCore/Services/MatchingService.swift` (the `resolve` function: step 1 accept override, step 4 family candidates)
- Test: `Tests/NorseMixologyCoreTests/CatalogToleranceTests.swift`

**Interfaces:**
- Consumes: `MatchingService.match(cabinet:recipes:index:prefs:)`, `TaxonomyIndex(categories:)`, `MatchPreferences.default`, `CabinetItem.init`.
- Produces: no API change.

- [ ] **Step 1: Write the failing tests**

`Tests/NorseMixologyCoreTests/CatalogToleranceTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

/// Spec row 16: a catalog update removed a style that is still in the user's cabinet.
final class CatalogToleranceTests: XCTestCase {
    private var index: TaxonomyIndex!
    private var recipes: [Recipe]!

    override func setUpWithError() throws {
        index = TaxonomyIndex(categories: try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData()))
        recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
    }

    private func style(_ name: String) throws -> IngredientStyle {
        try XCTUnwrap(index.stylesById.values.first { $0.name == name })
    }

    private func item(for style: IngredientStyle) -> CabinetItem {
        CabinetItem(ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
                    displayName: style.name, brand: nil, style: style.name,
                    family: index.familyName(for: style), category: index.categoryName(for: style),
                    flavorProfile: style.flavorProfile)
    }

    /// A cabinet snapshot of a gin style that no longer exists in the catalog,
    /// with a flavour profile identical to London Dry Gin.
    private func ghostGin() throws -> CabinetItem {
        let londonDry = try style("London Dry Gin")
        return CabinetItem(ingredientStyleId: UUID(), ingredientFamilyId: londonDry.familyId, categoryId: londonDry.categoryId,
                           displayName: "Discontinued Gin", brand: nil, style: "Discontinued Gin",
                           family: "Gin", category: "Spirit", flavorProfile: londonDry.flavorProfile)
    }

    private func summary(_ results: [RecipeMatchResult]) -> [String] {
        results.map { "\($0.recipe.name) \($0.matchType) \($0.matchScore)" }
    }

    func testGhostCabinetItemDoesNotChangeResults() throws {
        let vermouth = item(for: try style("Dry Vermouth"))
        let without = MatchingService.match(cabinet: [vermouth], recipes: recipes, index: index)
        let with = MatchingService.match(cabinet: [vermouth, try ghostGin()], recipes: recipes, index: index)
        XCTAssertEqual(summary(with), summary(without))
    }

    func testAcceptOverrideToAGhostStyleIsIgnored() throws {
        let londonDry = try style("London Dry Gin")
        let vermouth = item(for: try style("Dry Vermouth"))
        let ghost = try ghostGin()
        var prefs = MatchPreferences.default
        prefs.acceptOverrides[londonDry.id] = ghost.ingredientStyleId
        let without = MatchingService.match(cabinet: [vermouth], recipes: recipes, index: index, prefs: prefs)
        let with = MatchingService.match(cabinet: [vermouth, ghost], recipes: recipes, index: index, prefs: prefs)
        XCTAssertEqual(summary(with), summary(without))
    }

    func testRecipeIngredientMissingFromTheIndexDoesNotCrash() throws {
        let gin = item(for: try style("London Dry Gin"))
        let orphanIndex = TaxonomyIndex(categories: [])
        XCTAssertNoThrow(MatchingService.match(cabinet: [gin], recipes: recipes, index: orphanIndex))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CatalogToleranceTests`
Expected: `testGhostCabinetItemDoesNotChangeResults` and `testAcceptOverrideToAGhostStyleIsIgnored` FAIL (the `with` list contains gin recipes such as Martini that `without` lacks); `testRecipeIngredientMissingFromTheIndexDoesNotCrash` PASSES.

- [ ] **Step 3: Fix `resolve` in `MatchingService.swift`**

Step 1 (user accept override) — replace:

```swift
        if let acceptedId = prefs.acceptOverrides[requiredStyle.id],
           !prefs.isRejected(substituteId: acceptedId, for: requiredStyle.id),
           cabinetByStyleId[acceptedId] != nil {
            return .resolved(quality: 1.0, substituteStyle: stylesById[acceptedId])
        }
```

with:

```swift
        // A style that has left the catalog can't be a substitute (see CatalogToleranceTests).
        if let acceptedId = prefs.acceptOverrides[requiredStyle.id],
           !prefs.isRejected(substituteId: acceptedId, for: requiredStyle.id),
           cabinetByStyleId[acceptedId] != nil,
           let acceptedStyle = stylesById[acceptedId] {
            return .resolved(quality: 1.0, substituteStyle: acceptedStyle)
        }
```

Step 4 (family candidates) — replace:

```swift
            .filter { $0.ingredientStyleId != requiredStyle.id && !prefs.isRejected(substituteId: $0.ingredientStyleId, for: requiredStyle.id) }
```

with:

```swift
            .filter {
                $0.ingredientStyleId != requiredStyle.id
                    && stylesById[$0.ingredientStyleId] != nil // ghost cabinet items never substitute
                    && !prefs.isRejected(substituteId: $0.ingredientStyleId, for: requiredStyle.id)
            }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CatalogToleranceTests` → 3 PASS. Then `swift test` → all green (the existing `MatchingServiceTests` must be unchanged).

- [ ] **Step 5: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Services/MatchingService.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/CatalogToleranceTests.swift
git commit -m "iOS: cabinet items for styles removed from the catalog never substitute"
```

---

### Task 8: Sync the bundled snapshot from the published catalog

**Requires Plan 1 complete** (`curl -sSf https://martinloeseth.dev/norse-catalog/v1/manifest.json` succeeds). If it doesn't, stop and report; do not hand-write a manifest.

**Files:**
- Create: `scripts/sync-catalog.sh` (repo root)
- Create (by running the script): `seed-data/manifest.json`, `ios/NorseMixology/Resources/manifest.json`
- Delete: `seed-data/generate.py`
- Test: `ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/AppBundleCatalogTests.swift`

**Interfaces:**
- Consumes: the live manifest contract from Plan 1; `CatalogBootstrap.run`, `BundledCatalog`.
- Produces: `ios/NorseMixology/Resources/{manifest,taxonomy,recipes}.json` — Task 9 loads these from the app bundle.

- [ ] **Step 1: Write the failing test against the files the app actually ships**

`Tests/NorseMixologyCoreTests/AppBundleCatalogTests.swift`:

```swift
import XCTest
@testable import NorseMixologyCore

/// Reads ios/NorseMixology/Resources — the files the app ships — not the
/// test-target copies, so a bad sync can never reach a release build (row 17).
final class AppBundleCatalogTests: XCTestCase {
    private func appResource(_ name: String) throws -> Data {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NorseMixologyCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NorseMixologyCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios
        return try Data(contentsOf: ios.appending(path: "NorseMixology/Resources/\(name)"))
    }

    func testShippedCatalogBootstrapsCleanly() throws {
        let paths = try CatalogFixtures.tempPaths()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let bundled = BundledCatalog(
            manifestData: try appResource("manifest.json"),
            taxonomyData: try appResource("taxonomy.json"),
            recipesData: try appResource("recipes.json")
        )
        guard case .loaded(let catalog) = CatalogBootstrap.run(paths: paths, bundled: bundled) else {
            return XCTFail("the shipped catalog does not bootstrap")
        }
        XCTAssertEqual(catalog.meta.source, .bundled)
        XCTAssertGreaterThanOrEqual(catalog.recipes.count, 150)
    }

    func testTestResourcesMatchTheShippedCatalog() throws {
        XCTAssertEqual(try CatalogFixtures.taxonomyData(), try appResource("taxonomy.json"))
        XCTAssertEqual(try CatalogFixtures.recipesData(), try appResource("recipes.json"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppBundleCatalogTests`
Expected: `testShippedCatalogBootstrapsCleanly` FAILS (no `manifest.json` in `ios/NorseMixology/Resources`); `testTestResourcesMatchTheShippedCatalog` PASSES.

- [ ] **Step 3: Write the sync script**

`scripts/sync-catalog.sh`:

```bash
#!/usr/bin/env bash
# Pulls the published catalog (manifest + content-hashed files) into the app repo's
# bundled snapshot: seed-data/ (read by the Android build), the iOS app resources,
# and the core package's test resources. Verifies every hash before writing anything.
#
# Usage: scripts/sync-catalog.sh [BASE_URL]
#   BASE_URL defaults to https://martinloeseth.dev/norse-catalog
set -euo pipefail

BASE="${1:-https://martinloeseth.dev/norse-catalog}/v1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$BASE/manifest.json" -o "$TMP/manifest.json"

read -r TAX_PATH TAX_SHA REC_PATH REC_SHA < <(python3 - "$TMP/manifest.json" <<'EOF'
import json, re, sys
m = json.load(open(sys.argv[1]))
assert m["schemaVersion"] == 1, "unsupported schemaVersion %r" % m["schemaVersion"]
for key in ("taxonomy", "recipes"):
    assert re.fullmatch(key + r"\.[0-9a-f]{8}\.json", m[key]["path"]), "bad path %r" % m[key]["path"]
    assert re.fullmatch(r"[0-9a-f]{64}", m[key]["sha256"]), "bad sha256"
print(m["taxonomy"]["path"], m["taxonomy"]["sha256"], m["recipes"]["path"], m["recipes"]["sha256"])
EOF
)

curl -fsSL "$BASE/$TAX_PATH" -o "$TMP/taxonomy.json"
curl -fsSL "$BASE/$REC_PATH" -o "$TMP/recipes.json"
echo "$TAX_SHA  $TMP/taxonomy.json" | shasum -a 256 -c -
echo "$REC_SHA  $TMP/recipes.json" | shasum -a 256 -c -

for dest in "$ROOT/seed-data" "$ROOT/ios/NorseMixology/Resources"; do
  cp "$TMP/manifest.json" "$TMP/taxonomy.json" "$TMP/recipes.json" "$dest/"
done
cp "$TMP/taxonomy.json" "$TMP/recipes.json" "$ROOT/ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/Resources/"

python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print("Synced catalog", m["contentVersion"], "generated", m["generatedAt"])' "$TMP/manifest.json"
```

```bash
cd /Users/mlj/dev/norse-mixology
chmod +x scripts/sync-catalog.sh
scripts/sync-catalog.sh
git status --short
```

Expected: `taxonomy.json: OK`, `recipes.json: OK`, `Synced catalog <8 hex> ...`. `git status` shows **only** the two new `manifest.json` files as changes — the JSON files are byte-identical to before (Plan 1 Task 2 Step 5 proved this). If any `taxonomy.json`/`recipes.json` shows as modified, stop and report.

- [ ] **Step 4: Remove the generator from the app repo**

```bash
cd /Users/mlj/dev/norse-mixology
git rm seed-data/generate.py
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ios/Packages/NorseMixologyCore && swift test`
Expected: all tests PASS, including both `AppBundleCatalogTests`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mlj/dev/norse-mixology
git add scripts/sync-catalog.sh seed-data/manifest.json ios/NorseMixology/Resources/manifest.json \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/AppBundleCatalogTests.swift
git commit -m "Catalog: sync bundled snapshot from norse-catalog; generator moved out"
```

---

### Task 9: Wire the catalog into the app

**Files:**
- Modify: `Sources/NorseMixologyCore/Taxonomy/TaxonomyStore.swift`
- Modify: `Tests/NorseMixologyCoreTests/TaxonomyStoreTests.swift` (append 2 tests)
- Create: `ios/NorseMixology/Catalog/CatalogLaunch.swift`
- Modify: `ios/NorseMixology/NorseMixologyApp.swift`, `ios/NorseMixology/ContentView.swift`

**Interfaces:**
- Consumes: `CatalogBootstrap.run`, `BundledCatalog`, `CatalogPaths.applicationSupport()`, `CatalogUpdater`, `LoadedCatalog`, `CatalogMeta`.
- Produces: `TaxonomyStore.load(categories: [IngredientCategory], recipes: [Recipe])`, `TaxonomyStore.markUnavailable()`, `TaxonomyStore.isUnavailable: Bool`. Existing `load(taxonomyData:)` / `loadRecipes(from:)` stay (tests use them).

- [ ] **Step 1: Write the failing store tests** — append to `TaxonomyStoreTests`:

```swift
    func testLoadFromCatalogPopulatesTaxonomyAndRecipes() throws {
        let categories = try IngredientTaxonomy.loadCategories(from: CatalogFixtures.taxonomyData())
        let recipes = try IngredientTaxonomy.loadRecipes(from: CatalogFixtures.recipesData())
        let store = TaxonomyStore()
        store.load(categories: categories, recipes: recipes)

        XCTAssertTrue(store.isLoaded)
        XCTAssertTrue(store.recipesLoaded)
        XCTAssertFalse(store.isUnavailable)
        XCTAssertEqual(store.recipes, recipes)
        XCTAssertEqual(store.styleCount, IngredientTaxonomy.flattenStyles(categories).count)
        let ginStyle = try XCTUnwrap(store.stylesById.values.first { $0.name == "London Dry Gin" })
        XCTAssertEqual(store.familyNamesById[ginStyle.familyId], "Gin")
        XCTAssertEqual(store.categoryNamesById[ginStyle.categoryId], "Spirit")
    }

    func testMarkUnavailable() {
        let store = TaxonomyStore()
        store.markUnavailable()
        XCTAssertTrue(store.isUnavailable)
        XCTAssertFalse(store.isLoaded)
    }
```

Run: `swift test --filter TaxonomyStoreTests`
Expected: compile error — `value of type 'TaxonomyStore' has no member 'load(categories:recipes:)'`.

- [ ] **Step 2: Update `TaxonomyStore`**

Replace the doc comment and `load(taxonomyData:)` in `TaxonomyStore.swift`, and add the new members, so the file reads:

```swift
import Foundation
import Observation

/// In-memory cache of the catalog, loaded once per app launch from the
/// on-device catalog database (see `CatalogBootstrap`). The taxonomy itself is
/// read-only reference data — only `CabinetItem`s (copies of the fields a user
/// picks) are persisted in SwiftData.
@Observable
public final class TaxonomyStore {
    public private(set) var categories: [IngredientCategory] = []
    public private(set) var stylesById: [UUID: IngredientStyle] = [:]
    public private(set) var familyNamesById: [UUID: String] = [:]
    public private(set) var categoryNamesById: [UUID: String] = [:]
    public private(set) var isLoaded = false

    public private(set) var recipes: [Recipe] = []
    public private(set) var recipesLoaded = false

    /// True when no catalog could be loaded at all (spec row 17).
    public private(set) var isUnavailable = false

    public init() {}

    /// No-op if already loaded.
    public func load(categories: [IngredientCategory], recipes: [Recipe]) {
        guard !isLoaded else { return }
        apply(categories)
        self.recipes = recipes
        self.recipesLoaded = true
    }

    public func markUnavailable() {
        isUnavailable = true
    }

    /// No-op if already loaded — safe to call from multiple views without
    /// re-parsing the JSON.
    public func load(taxonomyData: Data) {
        guard !isLoaded else { return }
        guard let categories = try? IngredientTaxonomy.loadCategories(from: taxonomyData) else { return }
        apply(categories)
    }

    private func apply(_ categories: [IngredientCategory]) {
        var familyNames: [UUID: String] = [:]
        var categoryNames: [UUID: String] = [:]
        for category in categories {
            categoryNames[category.id] = category.name
            for family in category.families {
                familyNames[family.id] = family.name
            }
        }

        self.categories = categories
        self.stylesById = IngredientTaxonomy.flattenStyles(categories)
        self.familyNamesById = familyNames
        self.categoryNamesById = categoryNames
        self.isLoaded = true
    }
```

Keep `loadRecipes(from:)`, `styleCount` and `index` exactly as they are below this.

Run: `swift test` → all PASS.

- [ ] **Step 3: Add the app-side glue**

`ios/NorseMixology/Catalog/CatalogLaunch.swift`:

```swift
import Foundation
import NorseMixologyCore

enum CatalogConfig {
    static let baseURL = URL(string: "https://martinloeseth.dev/norse-catalog/")!
}

/// Connects the core catalog pipeline to this app: its bundle, its
/// Application Support directory, and its catalog host.
enum CatalogLaunch {
    static func bootstrap() -> CatalogBootstrapResult {
        let paths: CatalogPaths
        do {
            paths = try CatalogPaths.applicationSupport()
        } catch {
            return .unavailable(reason: "Application Support unavailable: \(error)")
        }
        return CatalogBootstrap.run(paths: paths, bundled: bundledCatalog())
    }

    static func refresh(current: CatalogMeta) async {
        guard let paths = try? CatalogPaths.applicationSupport() else { return }
        let outcome = await CatalogUpdater(baseURL: CatalogConfig.baseURL, paths: paths).refresh(current: current)
        switch outcome {
        case .failed(let error):
            AppLog.catalog.error("Catalog refresh failed: \(String(describing: error), privacy: .public)")
        default:
            AppLog.catalog.info("Catalog refresh: \(String(describing: outcome), privacy: .public)")
        }
    }

    /// Missing files become empty data, which the bootstrap treats as an
    /// unusable bundled catalog (and falls back to the stored one).
    private static func bundledCatalog() -> BundledCatalog {
        func resource(_ name: String) -> Data {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                AppLog.catalog.error("Bundled \(name, privacy: .public).json missing")
                return Data()
            }
            return data
        }
        return BundledCatalog(manifestData: resource("manifest"), taxonomyData: resource("taxonomy"), recipesData: resource("recipes"))
    }
}
```

- [ ] **Step 4: Replace the JSON loading in `NorseMixologyApp.swift`**

Replace `.task { loadBundledTaxonomyAndLog() }` with `.task { await loadCatalog() }`, and replace the whole `loadBundledTaxonomyAndLog()` function with:

```swift
    /// Opens (or rebuilds) the on-device catalog off the main thread, then
    /// checks for a newer one in the background — applied on the next launch.
    /// The taxonomy is read-only reference data — it is never written into
    /// SwiftData; only `CabinetItem`s and `FavouriteRecipe`s are persisted.
    @MainActor
    private func loadCatalog() async {
        guard !taxonomyStore.isLoaded else { return }
        let result = await Task.detached(priority: .userInitiated) { CatalogLaunch.bootstrap() }.value
        switch result {
        case .loaded(let catalog):
            taxonomyStore.load(categories: catalog.categories, recipes: catalog.recipes)
            AppLog.catalog.info("Catalog \(catalog.meta.contentVersion, privacy: .public) (\(catalog.meta.source.rawValue, privacy: .public)): \(taxonomyStore.styleCount) styles, \(catalog.recipes.count) recipes")
            let meta = catalog.meta
            Task.detached(priority: .background) { await CatalogLaunch.refresh(current: meta) }
        case .unavailable(let reason):
            AppLog.catalog.error("Catalog unavailable: \(reason, privacy: .public)")
            taxonomyStore.markUnavailable()
        }
    }
```

- [ ] **Step 5: Show the unavailable state in `ContentView.swift`**

Add `@Environment(TaxonomyStore.self) private var taxonomyStore` to `ContentView`, and wrap the body:

```swift
    var body: some View {
        if taxonomyStore.isUnavailable {
            ContentUnavailableView(
                "Catalog unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The recipe catalog couldn't be loaded. Reinstalling the app will restore it.")
            )
        } else {
            TabView(selection: $selectedTab) {
                // … existing tabs unchanged …
            }
            .environment(recipeBrowserViewModel)
        }
    }
```

(Keep the three existing tab items exactly as they are inside the `TabView`.)

- [ ] **Step 6: Build and refresh the string catalog**

```bash
cd /Users/mlj/dev/norse-mixology/ios
xcodegen generate
xcodebuild -project NorseMixology.xcodeproj -scheme NorseMixology \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
scripts/sync-strings.sh build/DerivedData
```

Expected: `** BUILD SUCCEEDED **`; `Localizable.xcstrings` gains the two new strings.

- [ ] **Step 7: Smoke-test in the simulator**

```bash
cd /Users/mlj/dev/norse-mixology/ios
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/NorseMixology.app
xcrun simctl uninstall booted dev.martinloeseth.NorseMixology || true
xcrun simctl install booted "$APP"
xcrun simctl launch booted dev.martinloeseth.NorseMixology
sleep 5
xcrun simctl spawn booted log show --last 1m --style compact \
  --predicate 'subsystem == "dev.martinloeseth.NorseMixology" AND category == "catalog"'
```

Expected log lines: `No catalog database yet; building from the bundled catalog`, `Catalog <8 hex> (bundled): <n> styles, <n> recipes`, and `Catalog refresh: upToDate` (the bundled snapshot equals the published one). Then relaunch (`xcrun simctl terminate booted dev.martinloeseth.NorseMixology && xcrun simctl launch booted dev.martinloeseth.NorseMixology`) and confirm the "building from the bundled catalog" line does **not** reappear. Take a screenshot (`xcrun simctl io booted screenshot /tmp/catalog-smoke.png`) and confirm the Recipes tab lists recipes.

- [ ] **Step 8: Run all core tests and commit**

```bash
cd /Users/mlj/dev/norse-mixology/ios/Packages/NorseMixologyCore && swift test
cd /Users/mlj/dev/norse-mixology
git add ios/Packages/NorseMixologyCore/Sources/NorseMixologyCore/Taxonomy/TaxonomyStore.swift \
  ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/TaxonomyStoreTests.swift \
  ios/NorseMixology/Catalog ios/NorseMixology/NorseMixologyApp.swift ios/NorseMixology/ContentView.swift \
  ios/NorseMixology/Localizable.xcstrings ios/NorseMixology.xcodeproj
git commit -m "iOS: load the catalog from SQLite at launch and refresh it in the background"
```

---

### Task 10: Documentation

**Files:**
- Modify: `NORSE_MIXOLOGY_BUILD.md` (repo root)
- Modify (Obsidian vault, `/Users/mlj/Library/Mobile Documents/iCloud~md~obsidian/Documents/Project Ideas/Dev Project Ideas/Norse Mixology/`): `Backend (Rust) - Future Release.md`, `System Design (Rust Backend) - Future Release.md`, `Deployment.md`, `Data Model.md`

- [ ] **Step 1: `NORSE_MIXOLOGY_BUILD.md`**

In the "Android data layer & seeding (Phase 7)" section, replace the bullet starting `- **One catalog source of truth.**` with:

```markdown
- **One catalog source of truth.** The catalog is authored in the public `norse-catalog` repo (`generate.py` → validated → published to GitHub Pages). `scripts/sync-catalog.sh` copies the published `manifest.json` + `taxonomy.json` + `recipes.json` into `/seed-data` and `ios/NorseMixology/Resources` (and the iOS core test resources). Android copies just `taxonomy.json` + `recipes.json` from `/seed-data` into generated assets at build time (`copySeedData` task). A unit test asserts that `ios/NorseMixology/Resources/*.json` is byte-identical to `/seed-data` — always update both via the sync script.
```

Then add a new section after "Hardening rules (Phase 6 — Android Phase 10 must match)":

```markdown
## Catalog delivery (iOS)

- **Source:** `https://martinloeseth.dev/norse-catalog/v1/manifest.json` → content-hashed `taxonomy.<sha8>.json` / `recipes.<sha8>.json`. Spec: `docs/superpowers/specs/2026-09-23-catalog-delivery-design.md`.
- **On device:** `Application Support/Catalog/catalog.sqlite` (GRDB, `STRICT` tables, foreign keys, 0–1 `CHECK`s, `user_version` = `CatalogSchema.version`). Built only by `CatalogImporter` from hash-verified JSON; read only by `CatalogDatabase` (read-only, then closed — `TaxonomyStore` holds the catalog in memory).
- **Launch:** `CatalogBootstrap` removes staging leftovers, loads the live DB, and rebuilds from the bundled snapshot if it's missing, corrupt, a different schema version, or older than the bundle. If that fails it keeps an older valid DB, else the app shows "Catalog unavailable".
- **Refresh:** `CatalogUpdater` runs after the UI is up on every cold launch: conditional GET with the stored ETag, 64 KB manifest cap, 2 MB file caps enforced while streaming, SHA-256 checks, import into `catalog.new.sqlite`, atomic replace. New content applies on the **next** launch. A manifest whose `generatedAt` isn't newer than the current catalog is ignored.
- **Bump `CatalogSchema.version`** whenever the SQLite schema changes; the bootstrap rebuilds on mismatch.
- **Remote updates reject the whole catalog on any malformed recipe** (unlike the tolerant bundled-era loader).
- **Styles removed from the catalog** stay in cabinets as snapshots but never act as substitutes (`MatchingService.resolve`).
- **Before an app release:** run `scripts/sync-catalog.sh` so the bundled fallback is current.
```

- [ ] **Step 2: Obsidian — `Backend (Rust) - Future Release.md`**

Directly under the `> 🔵 **Future release** …` banner, add:

```markdown
> **2026-09-23 update:** Catalog *delivery* (the read endpoints below) no longer needs this service. The taxonomy and recipes are published as static, content-hashed JSON on GitHub Pages from the public `norse-catalog` repo, and the iOS app imports them into an on-device SQLite catalog. See `docs/superpowers/specs/2026-09-23-catalog-delivery-design.md` in the app repo. The Rust service is deferred until server-side matching (`POST /recipes/match`) is built; when it is, it reads the catalog from the same Pages manifest, and Postgres is not needed for read-only content.
```

- [ ] **Step 3: Obsidian — `System Design (Rust Backend) - Future Release.md`**

At the top of "## 4. Taxonomy versioning with eTag", add:

```markdown
> **Superseded for catalog delivery (2026-09-23):** implemented as a static `manifest.json` on GitHub Pages instead of a `/taxonomy` endpoint — Pages supplies the ETag/304, and `contentVersion` + `generatedAt` in the manifest replace the date-and-counter ETag. See the catalog delivery spec in the app repo.
```

- [ ] **Step 4: Obsidian — `Deployment.md`**

In "## Backend", after the existing paragraph, add:

```markdown
**Catalog hosting (since 2026-09-23):** the public `norse-catalog` GitHub repo publishes the catalog to `https://martinloeseth.dev/norse-catalog/v1/` via GitHub Actions (free). Workflow: edit `generate.py` → `python3 -m catalog.build` → commit `site/` → PR (CI checks) → merge (deploys). Before each app release, run `scripts/sync-catalog.sh` in the app repo to refresh the bundled fallback.
```

- [ ] **Step 5: Obsidian — `Data Model.md`**

Next to the existing "Dual-platform note" paragraph about `recipes.json`, add:

```markdown
**Storage (iOS, since 2026-09-23):** the catalog JSON is imported into an on-device SQLite database (`catalog.sqlite`, GRDB) and refreshed over the air from GitHub Pages; the JSON shape above is unchanged and is still the wire format. Android still seeds Room from the bundled JSON (paused).
```

- [ ] **Step 6: Commit the repo doc change**

```bash
cd /Users/mlj/dev/norse-mixology
git add NORSE_MIXOLOGY_BUILD.md
git commit -m "docs: catalog delivery section in the build reference"
```

(The Obsidian vault is not a git repo — no commit for Steps 2–5.)
