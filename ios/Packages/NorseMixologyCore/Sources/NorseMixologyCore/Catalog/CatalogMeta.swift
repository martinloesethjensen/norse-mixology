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
