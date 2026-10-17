import Foundation

/// Free space checks, so a full disk reads "There isn't enough free space"
/// instead of "This file isn't a Norse Mixology backup" (Backup spec §5).
/// AppleArchive's errors carry no errno, so the check is made by size.
public enum BackupSpace {
    /// Below this, a failed write is reported as out of space.
    static let nearlyFull: Int64 = 100_000_000

    /// Bytes available on the volume holding `url`, or nil if unknown.
    public static func available(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
}
