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
