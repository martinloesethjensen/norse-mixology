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
