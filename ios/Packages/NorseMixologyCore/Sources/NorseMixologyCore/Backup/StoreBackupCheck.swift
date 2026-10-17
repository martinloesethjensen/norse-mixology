import Foundation

/// Makes sure the SwiftData store is included in iCloud/Finder device backups —
/// the "lost my phone" path (Backup spec §1).
public enum StoreBackupCheck {
    /// Clears the "excluded from backup" flag if something set it. Returns true when it had to.
    @discardableResult
    public static func ensureIncluded(_ storeURL: URL) -> Bool {
        var url = storeURL
        guard let values = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]),
              values.isExcludedFromBackup == true else { return false }
        var newValues = URLResourceValues()
        newValues.isExcludedFromBackup = false
        do {
            try url.setResourceValues(newValues)
            AppLog.backup.notice("Store was excluded from device backup; included it again")
            return true
        } catch {
            AppLog.backup.error("Could not include the store in device backup: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
