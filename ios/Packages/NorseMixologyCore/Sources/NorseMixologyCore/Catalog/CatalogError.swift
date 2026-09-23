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
