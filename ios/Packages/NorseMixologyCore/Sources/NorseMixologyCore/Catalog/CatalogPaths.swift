import Foundation

/// Where the catalog database lives, and the two file operations that make
/// updates atomic: throw away a half-built staging file, and swap a finished
/// one into place in a single rename.
///
/// Every build attempt stages into its own file (`catalog.new.<uuid>.sqlite`),
/// so two attempts in one process — e.g. two iPad scenes launching together —
/// can never unlink or promote each other's half-written database.
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

    private static let stagingPrefix = "catalog.new"

    /// A fresh staging URL for one build attempt. Nothing is created on disk.
    public func makeStaging() -> URL {
        directory.appending(path: "\(Self.stagingPrefix).\(UUID().uuidString).sqlite")
    }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Removes one attempt's staging file and its SQLite sidecars.
    public func removeStaging(_ staging: URL) {
        Self.removeDatabaseFiles(at: staging)
    }

    /// Removes every staging file (and sidecar) in the directory, including the
    /// fixed `catalog.new.sqlite` name used by earlier builds. Only safe when no
    /// other attempt is running — i.e. at bootstrap, before any update starts.
    public func removeAllStaging() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(Self.stagingPrefix) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// Atomically replaces `live` with `staging`. If this throws, `live` is untouched.
    public func promote(_ staging: URL) throws {
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
