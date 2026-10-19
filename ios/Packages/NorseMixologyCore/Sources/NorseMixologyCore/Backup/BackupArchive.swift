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

    /// More than any real backup unpacks to (6 photos on every recipe is about 0.5 GB).
    static let maxUnpackedBytes: Int64 = 2 << 30

    /// Throws `.notABackup` for anything that is not a readable archive, and `.damaged`
    /// when it unpacks to more than `limit` bytes: a small file can decompress to
    /// something huge, so the cap is checked while it streams, before the disk fills.
    static func unpack(_ file: URL, into directory: URL, limit: Int64 = maxUnpackedBytes) throws {
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
        let capped = CappedByteStream(reading: decompressStream, limit: limit)
        guard let cappedStream = ArchiveByteStream.customStream(instance: capped) else { throw BackupError.notABackup }
        defer { try? cappedStream.close() }
        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: cappedStream) else { throw BackupError.notABackup }
        defer { try? decodeStream.close() }
        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: FilePath(directory.path), flags: [.ignoreOperationNotPermitted]) else { throw BackupError.notABackup }
        defer { try? extractStream.close() }
        do {
            _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
        } catch {
            throw capped.exceeded ? BackupError.damaged : BackupError.notABackup
        }
    }
}

/// Passes reads through to `inner` until more than `limit` bytes have come out of it.
/// Read-only and sequential, which is all the decoder needs.
private final class CappedByteStream: ArchiveByteStreamProtocol {
    private struct OverLimit: Error {}

    private let inner: ArchiveByteStream
    private let limit: Int64
    private var total: Int64 = 0
    private(set) var exceeded = false

    init(reading inner: ArchiveByteStream, limit: Int64) {
        self.inner = inner
        self.limit = limit
    }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let count = try inner.read(into: buffer)
        total += Int64(count)
        guard total <= limit else {
            exceeded = true
            throw OverLimit()
        }
        return count
    }

    func read(into buffer: UnsafeMutableRawBufferPointer, atOffset offset: Int64) throws -> Int { throw OverLimit() }
    func write(from buffer: UnsafeRawBufferPointer) throws -> Int { throw OverLimit() }
    func write(from buffer: UnsafeRawBufferPointer, atOffset offset: Int64) throws -> Int { throw OverLimit() }
    func seek(toOffset offset: Int64, relativeTo whence: FileDescriptor.SeekOrigin) throws -> Int64 { throw OverLimit() }
    func cancel() { inner.cancel() }
    func close() throws {} // `inner` is closed by its owner
}
