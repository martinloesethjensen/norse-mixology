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
    func testLeftoverStagingFilesAreRemoved() throws {
        // Two per-attempt leftovers plus the fixed name used by earlier builds, each with a sidecar.
        let leftovers = [paths.makeStaging(), paths.makeStaging(), paths.directory.appending(path: "catalog.new.sqlite")]
        for url in leftovers {
            try Data("half-written".utf8).write(to: url)
            try Data("journal".utf8).write(to: URL(fileURLWithPath: url.path + "-journal"))
        }
        _ = try loaded(CatalogBootstrap.run(paths: paths, bundled: bundled()))
        XCTAssertEqual(try CatalogFixtures.stagingFiles(in: paths), [])
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
        XCTAssertEqual(try CatalogFixtures.stagingFiles(in: paths), [])
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
