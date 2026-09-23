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
