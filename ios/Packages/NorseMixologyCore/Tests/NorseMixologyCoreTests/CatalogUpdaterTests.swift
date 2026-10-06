import CryptoKit
import XCTest
@testable import NorseMixologyCore

final class CatalogUpdaterTests: XCTestCase {
    private let baseURL = URL(string: "https://catalog.test/norse-catalog/")!
    private var paths: CatalogPaths!
    private var current: CatalogMeta!
    private var remoteTaxonomy: Data!
    private var remoteRecipes: Data!
    private var remoteManifest: CatalogManifest!
    private let signingKey = Curve25519.Signing.PrivateKey()
    /// The device clock: an hour after the remote manifest was generated.
    private let now = CatalogFixtures.t0.addingTimeInterval(7200)

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

    private func updater(
        trusting keys: [Curve25519.Signing.PublicKey]? = nil,
        promote: (@Sendable (CatalogPaths, URL) throws -> Void)? = nil
    ) -> CatalogUpdater {
        let signingKeys = CatalogSigningKeys(keys: keys ?? [signingKey.publicKey])
        let now = self.now
        if let promote {
            return CatalogUpdater(baseURL: baseURL, signingKeys: signingKeys, session: StubURLProtocol.session(), paths: paths,
                                  now: { now }, promote: promote)
        }
        return CatalogUpdater(baseURL: baseURL, signingKeys: signingKeys, session: StubURLProtocol.session(), paths: paths, now: { now })
    }

    /// `manifest.json.sig` as the publish job writes it: base64 plus a newline.
    private func signatureFile(for data: Data, key: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        Data((try (key ?? signingKey).signature(for: data).base64EncodedString() + "\n").utf8)
    }

    /// Serves `manifest`, its signature (by default a valid one) and the two
    /// remote files; anything else is a 404.
    private func serve(
        manifest: Data? = nil,
        manifestStatus: Int = 200,
        signature: Data? = nil,
        signatureStatus: Int = 200,
        taxonomyBody: Data? = nil,
        recipesBody: Data? = nil
    ) throws {
        let manifestData = try manifest ?? CatalogFixtures.encode(remoteManifest)
        let signatureData = try signature ?? signatureFile(for: manifestData)
        let taxonomyPath = remoteManifest.taxonomy.path
        let recipesPath = remoteManifest.recipes.path
        let taxonomy = taxonomyBody ?? remoteTaxonomy!
        let recipes = recipesBody ?? remoteRecipes!
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/norse-catalog/v1/manifest.json":
                return .init(status: manifestStatus, headers: ["ETag": "\"new\""], body: manifestStatus == 304 ? Data() : manifestData)
            case "/norse-catalog/v1/manifest.json.sig":
                return .init(status: signatureStatus, body: signatureData)
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
        XCTAssertEqual(try CatalogFixtures.stagingFiles(in: paths), [], "staging left behind", file: file, line: line)
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
        XCTAssertEqual(try CatalogFixtures.stagingFiles(in: paths), [])
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
        XCTAssertEqual(StubURLProtocol.requests.count, 2, "only the manifest and its signature should be fetched")
        try assertLiveUnchanged()
    }

    // Row 2 (client side): a CDN-stale manifest must not downgrade the catalog.
    func testOlderManifestIsIgnored() async throws {
        remoteManifest = CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: remoteRecipes,
                                                  generatedAt: CatalogFixtures.t0.addingTimeInterval(-3600), contentVersion: "cccccccc")
        try serve()
        let outcome = await updater().refresh(current: current)
        XCTAssertEqual(outcome, .upToDate)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
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
        let manifestData = try CatalogFixtures.encode(remoteManifest)
        let signatureData = try signatureFile(for: manifestData)
        StubURLProtocol.handler = { request in
            switch request.url?.lastPathComponent {
            case "manifest.json": return .init(body: manifestData)
            case "manifest.json.sig": return .init(body: signatureData)
            default: return .init(status: 404)
            }
        }
        assertFailed(await updater().refresh(current: current)) { $0 == .http(status: 404) }
        XCTAssertEqual(StubURLProtocol.requests.count, 3, "manifest, signature, then the missing taxonomy")
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

    // MARK: - Signed manifest

    func testUnsignedManifestIsRejectedBeforeAnyFileIsFetched() async throws {
        try serve(signatureStatus: 404)
        assertFailed(await updater().refresh(current: current)) { $0 == .http(status: 404) }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        try assertLiveUnchanged()
    }

    func testManifestSignedByAnUntrustedKeyIsRejected() async throws {
        let manifestData = try CatalogFixtures.encode(remoteManifest)
        try serve(signature: signatureFile(for: manifestData, key: Curve25519.Signing.PrivateKey()))
        assertFailed(await updater().refresh(current: current)) { $0 == .invalidSignature }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        try assertLiveUnchanged()
    }

    func testTamperedManifestIsRejected() async throws {
        let signedData = try CatalogFixtures.encode(remoteManifest)
        let tampered = try CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: CatalogFixtures.recipesData(),
                                                generatedAt: remoteManifest.generatedAt, contentVersion: "bbbbbbbb")
        try serve(manifest: CatalogFixtures.encode(tampered), signature: signatureFile(for: signedData))
        assertFailed(await updater().refresh(current: current)) { $0 == .invalidSignature }
        try assertLiveUnchanged()
    }

    func testMalformedSignatureIsRejected() async throws {
        try serve(signature: Data("<html>not a signature</html>".utf8))
        assertFailed(await updater().refresh(current: current)) { $0 == .invalidSignature }
        try assertLiveUnchanged()
    }

    func testAnyTrustedKeyIsAccepted() async throws {
        try serve()
        let retiring = Curve25519.Signing.PrivateKey().publicKey
        let outcome = await updater(trusting: [retiring, signingKey.publicKey]).refresh(current: current)
        XCTAssertEqual(outcome, .updated(contentVersion: "bbbbbbbb"))
    }

    func testSigningKeysMustBeRawEd25519Keys() throws {
        let raw = signingKey.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertNoThrow(try CatalogSigningKeys(base64Keys: [raw]))
        XCTAssertThrowsError(try CatalogSigningKeys(base64Keys: []))
        XCTAssertThrowsError(try CatalogSigningKeys(base64Keys: ["REPLACE_WITH_CATALOG_SIGNING_PUBLIC_KEY"]))
        XCTAssertThrowsError(try CatalogSigningKeys(base64Keys: [Data(repeating: 1, count: 16).base64EncodedString()]))
    }

    // MARK: - Future-dated manifest

    func testFutureDatedManifestIsRejected() async throws {
        remoteManifest = CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: remoteRecipes,
                                                  generatedAt: now.addingTimeInterval(CatalogUpdater.maxClockSkew + 1), contentVersion: "bbbbbbbb")
        try serve()
        assertFailed(await updater().refresh(current: current)) { if case .invalidManifest = $0 { return true }; return false }
        XCTAssertEqual(StubURLProtocol.requests.count, 2, "no files should be fetched")
        try assertLiveUnchanged()
    }

    func testManifestSlightlyAheadOfTheDeviceClockIsAccepted() async throws {
        remoteManifest = CatalogFixtures.manifest(taxonomy: remoteTaxonomy, recipes: remoteRecipes,
                                                  generatedAt: now.addingTimeInterval(3600), contentVersion: "bbbbbbbb")
        try serve()
        let outcome = await updater().refresh(current: current)
        XCTAssertEqual(outcome, .updated(contentVersion: "bbbbbbbb"))
    }

    // MARK: - Row 12: swap fails

    func testFailedSwapLeavesTheLiveCatalogUntouched() async throws {
        try serve()
        let outcome = await updater(promote: { _, _ in throw CocoaError(.fileWriteUnknown) }).refresh(current: current)
        assertFailed(outcome) { if case .fileSystem = $0 { return true }; return false }
        try assertLiveUnchanged()
    }
}
