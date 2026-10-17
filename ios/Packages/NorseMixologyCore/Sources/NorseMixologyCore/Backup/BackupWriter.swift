import Foundation
import SwiftData

/// Writes everything the user has made into one `.nmbackup` file (Backup spec §3).
///
/// Call off the main actor. It reads through its own `ModelContext`s, so it sees
/// saved data only — callers save the main context first. Photos are written one
/// at a time, each read through a short-lived context, so a large library is
/// never held in memory at once.
public enum BackupWriter {
    /// Every temporary folder the backup code creates starts with this, so
    /// `cleanUpStaleFiles` can remove leftovers after a crash or kill.
    public static let temporaryPrefix = "NorseMixologyBackup-"

    public static func write(container: ModelContainer, appVersion: String, now: Date = Date(),
                             temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let fileManager = FileManager.default
        let workspace = temporaryDirectory.appendingPathComponent(temporaryPrefix + UUID().uuidString, isDirectory: true)
        let staging = workspace.appendingPathComponent("staging", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging.appendingPathComponent("photos", isDirectory: true),
                                            withIntermediateDirectories: true)
            try stage(container: container, appVersion: appVersion, now: now, into: staging)
            let archive = workspace.appendingPathComponent(fileName(for: now))
            try BackupArchive.pack(directory: staging, into: archive)
            try? fileManager.removeItem(at: staging)
            return archive
        } catch {
            try? fileManager.removeItem(at: workspace)
            AppLog.backup.error("Backup failed: \(String(describing: error), privacy: .public)")
            throw BackupError.from(error, otherwise: .exportFailed)
        }
    }

    /// `Norse Mixology Backup 2026-10-17.nmbackup`, in the device's time zone.
    public static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Norse Mixology Backup \(formatter.string(from: date)).nmbackup"
    }

    /// Removes leftover backup folders from an earlier run (called at launch).
    public static func cleanUpStaleFiles(in temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for item in items where item.lastPathComponent.hasPrefix(temporaryPrefix) {
            try? fileManager.removeItem(at: item)
        }
    }

    @discardableResult
    static func stage(container: ModelContainer, appVersion: String, now: Date, into folder: URL) throws -> BackupManifest {
        let context = ModelContext(container)
        let cabinet = try context.fetch(FetchDescriptor<CabinetItem>()).map(CabinetRecord.init)
        let favourites = try context.fetch(FetchDescriptor<FavouriteRecipe>()).map(FavouriteRecord.init)
        let shopping = try context.fetch(FetchDescriptor<ShoppingItem>()).map(ShoppingRecord.init)
        let takes = try context.fetch(FetchDescriptor<RecipeTake>()).map(TakeRecord.init)

        var headerDescriptor = FetchDescriptor<RecipePhoto>(sortBy: [SortDescriptor(\.dateAdded)])
        headerDescriptor.propertiesToFetch = [\.id, \.recipeId, \.dateAdded]
        let headers = try context.fetch(headerDescriptor).map { (id: $0.id, recipeId: $0.recipeId, dateAdded: $0.dateAdded) }

        var photos: [PhotoRecord] = []
        for header in headers {
            try autoreleasepool {
                let photoContext = ModelContext(container)
                guard let photo = RecipeTakeService.photo(id: header.id, context: photoContext) else { return }
                let paths = PhotoRecord.paths(for: header.id)
                try photo.full.write(to: folder.appendingPathComponent(paths.full))
                try photo.thumbnail.write(to: folder.appendingPathComponent(paths.thumbnail))
                photos.append(PhotoRecord(id: header.id, recipeId: header.recipeId, dateAdded: header.dateAdded,
                                          fullFile: paths.full, thumbnailFile: paths.thumbnail))
            }
        }

        let manifest = BackupManifest(appVersion: appVersion, createdAt: now, cabinet: cabinet, favourites: favourites,
                                      shopping: shopping, takes: takes, photos: photos)
        try BackupJSON.encoder().encode(manifest).write(to: folder.appendingPathComponent(BackupManifest.fileName))
        return manifest
    }
}
