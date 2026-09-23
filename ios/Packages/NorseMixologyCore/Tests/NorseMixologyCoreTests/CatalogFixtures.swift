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
