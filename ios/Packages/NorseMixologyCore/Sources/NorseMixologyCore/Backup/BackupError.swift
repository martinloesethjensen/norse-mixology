import Foundation

/// Everything that can go wrong with a backup, as the user sees it (Backup spec §3–4).
public enum BackupError: Error, Equatable, Sendable {
    /// Not an archive, empty, or an archive without a manifest.
    case notABackup
    /// Made by a newer version of the app (`formatVersion` too high).
    case newerVersion
    /// An archive with a broken manifest, a missing or unsafe photo path, or invalid values.
    case damaged
    case outOfSpace
    /// Writing the backup failed for a reason other than space.
    case exportFailed
    /// The restore could not be saved; it was rolled back, so nothing changed.
    case restoreFailed

    /// Maps any error to a `BackupError`: backup errors pass through, a full disk
    /// becomes `.outOfSpace`, anything else becomes `fallback`.
    public static func from(_ error: Error, otherwise fallback: BackupError) -> BackupError {
        if let backupError = error as? BackupError { return backupError }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) { return .outOfSpace }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError { return .outOfSpace }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return from(underlying, otherwise: fallback)
        }
        return fallback
    }
}
