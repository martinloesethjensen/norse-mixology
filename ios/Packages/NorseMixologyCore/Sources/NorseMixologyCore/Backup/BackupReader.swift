import Foundation

/// What a backup contains, shown before the user confirms a restore.
public struct BackupSummary: Equatable, Sendable {
    public var createdAt: Date
    public var cabinetItems: Int
    public var favourites: Int
    public var shoppingItems: Int
    public var takes: Int
    public var photos: Int
}

/// A backup unpacked into a temporary folder and fully validated. `close()` removes the folder.
public struct OpenedBackup: Sendable {
    public let manifest: BackupManifest
    let folder: URL
    let workspace: URL

    public var summary: BackupSummary {
        BackupSummary(createdAt: manifest.createdAt, cabinetItems: manifest.cabinet.count, favourites: manifest.favourites.count,
                      shoppingItems: manifest.shopping.count, takes: manifest.takes.count, photos: manifest.photos.count)
    }

    func url(for relativePath: String) -> URL {
        folder.appendingPathComponent(relativePath)
    }

    public func close() {
        try? FileManager.default.removeItem(at: workspace)
    }
}

/// Opens a `.nmbackup` file and refuses anything that could hurt the store
/// (Backup spec §3, §5). All checks happen before a restore touches the store.
public enum BackupReader {
    public static func open(_ file: URL,
                            temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                            availableSpace: (URL) -> Int64? = BackupSpace.available(at:)) throws -> OpenedBackup {
        let fileManager = FileManager.default
        // Unpacked photos are about the size of the (already compressed) file; allow twice that.
        let fileSize = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if let free = availableSpace(temporaryDirectory), free < fileSize * 2 {
            AppLog.backup.error("Backup refused: not enough free space")
            throw BackupError.outOfSpace
        }
        let workspace = temporaryDirectory.appendingPathComponent(BackupWriter.temporaryPrefix + UUID().uuidString,
                                                                  isDirectory: true)
        let folder = workspace.appendingPathComponent("contents", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try BackupArchive.unpack(file, into: folder)
            var manifest = try readManifest(in: folder)
            try validate(&manifest, in: folder)
            return OpenedBackup(manifest: manifest, folder: folder, workspace: workspace)
        } catch {
            try? fileManager.removeItem(at: workspace)
            let mapped = BackupError.from(error, otherwise: .damaged)
            AppLog.backup.error("Backup refused: \(String(describing: mapped), privacy: .public)")
            throw mapped
        }
    }

    private struct VersionProbe: Decodable {
        let formatVersion: Int
    }

    static func readManifest(in folder: URL) throws -> BackupManifest {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(BackupManifest.fileName)) else {
            throw BackupError.notABackup
        }
        // Read the version on its own first, so a newer file is reported as newer even if its shape changed.
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { throw BackupError.damaged }
        guard probe.formatVersion <= BackupManifest.currentFormatVersion else { throw BackupError.newerVersion }
        guard probe.formatVersion >= 1,
              let manifest = try? BackupJSON.decoder().decode(BackupManifest.self, from: data) else {
            throw BackupError.damaged
        }
        return manifest
    }

    static func validate(_ manifest: inout BackupManifest, in folder: URL) throws {
        for index in manifest.takes.indices {
            guard TakeLimits.ratingRange.contains(manifest.takes[index].rating) else { throw BackupError.damaged }
            manifest.takes[index].notes = String(manifest.takes[index].notes.prefix(TakeLimits.maxNotesLength))
        }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for photo in manifest.photos {
            for path in [photo.fullFile, photo.thumbnailFile] {
                guard isSafe(path) else { throw BackupError.damaged }
                let resolved = folder.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(root) else { throw BackupError.damaged }
                let values = try? resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 else { throw BackupError.damaged }
            }
        }
    }

    /// Only plain relative paths under `photos/`: no absolute paths, no `..`.
    static func isSafe(_ path: String) -> Bool {
        !path.hasPrefix("/") && path.hasPrefix("photos/") && !path.split(separator: "/").contains("..")
    }
}
