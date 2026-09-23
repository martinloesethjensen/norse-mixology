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
