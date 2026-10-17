import Foundation
import AppleArchive
import System

/// Packs a folder into one AppleArchive file (LZFSE) and unpacks it again.
/// iOS has no public zip API; AppleArchive is built in (iOS 14+, macOS 11+).
enum BackupArchive {
    static func pack(directory: URL, into file: URL) throws {
        guard let fileStream = ArchiveByteStream.fileStream(
            path: FilePath(file.path), mode: .writeOnly, options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)) else { throw BackupError.exportFailed }
        defer { try? fileStream.close() }
        guard let compressStream = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: fileStream) else {
            throw BackupError.exportFailed
        }
        defer { try? compressStream.close() }
        guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream) else { throw BackupError.exportFailed }
        defer { try? encodeStream.close() }
        guard let keys = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD") else { throw BackupError.exportFailed }
        try encodeStream.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keys)
    }

    /// Throws `.notABackup` for anything that is not a readable archive.
    static func unpack(_ file: URL, into directory: URL) throws {
        // An empty file decodes as an empty archive; it is still not a backup.
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { throw BackupError.notABackup }
        guard let fileStream = ArchiveByteStream.fileStream(
            path: FilePath(file.path), mode: .readOnly, options: [],
            permissions: FilePermissions(rawValue: 0o644)) else { throw BackupError.notABackup }
        defer { try? fileStream.close() }
        guard let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: fileStream) else {
            throw BackupError.notABackup
        }
        defer { try? decompressStream.close() }
        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream) else { throw BackupError.notABackup }
        defer { try? decodeStream.close() }
        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: FilePath(directory.path), flags: [.ignoreOperationNotPermitted]) else { throw BackupError.notABackup }
        defer { try? extractStream.close() }
        do {
            _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
        } catch {
            throw BackupError.notABackup
        }
    }
}
