import Foundation
import SwiftData
import ZIPFoundation

/// Writes everything the user created to one `.norsebackup` file (Backup spec §2, §3).
/// The caller owns the `ModelContext`; the app runs this off the main actor with a
/// context of its own. Photos are written one at a time, never all held at once.
public enum BackupExporter {
    @discardableResult
    public static func export(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        catalogContentVersion: String?,
        appVersion: String,
        to url: URL,
        now: Date = Date()
    ) throws -> BackupManifest {
        let data = try snapshot(context: context, defaults: defaults)
        let manifest = BackupManifest(
            format: BackupFormat.identifier, formatVersion: BackupFormat.version, createdAt: now,
            appVersion: appVersion, catalogContentVersion: catalogContentVersion, counts: data.counts)

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            let archive = try Archive(url: url, accessMode: .create)
            let encoder = BackupFormat.encoder()
            try add(try encoder.encode(manifest), path: BackupFormat.manifestPath, compressed: true, to: archive, date: now)
            try add(try encoder.encode(data), path: BackupFormat.dataPath, compressed: true, to: archive, date: now)
            for record in data.photos {
                let full = try fullImage(record.id, context: context)
                // Already JPEG, so deflating would only cost time.
                try add(full, path: record.file, compressed: false, to: archive, date: now)
            }
        } catch {
            try? fileManager.removeItem(at: url)
            throw BackupError.writeFailed
        }
        return manifest
    }

    /// The store and preferences as plain records, sorted so the same data always
    /// produces the same `data.json`.
    static func snapshot(context: ModelContext, defaults: UserDefaults) throws -> BackupData {
        let cabinet = try context.fetch(FetchDescriptor<CabinetItem>()).map {
            BackupData.CabinetItemRecord(
                id: $0.id, ingredientStyleId: $0.ingredientStyleId, ingredientFamilyId: $0.ingredientFamilyId,
                categoryId: $0.categoryId, displayName: $0.displayName, brand: $0.brand, style: $0.style,
                family: $0.family, category: $0.category, flavorProfile: $0.flavorProfile, dateAdded: $0.dateAdded)
        }
        let favourites = try context.fetch(FetchDescriptor<FavouriteRecipe>()).map {
            BackupData.FavouriteRecord(id: $0.id, recipeId: $0.recipeId, recipeName: $0.recipeName, dateFavourited: $0.dateFavourited)
        }
        let shopping = try context.fetch(FetchDescriptor<ShoppingItem>()).map {
            BackupData.ShoppingItemRecord(id: $0.id, ingredientStyleId: $0.ingredientStyleId, styleName: $0.styleName, dateAdded: $0.dateAdded)
        }
        let takes = try context.fetch(FetchDescriptor<RecipeTake>()).map {
            BackupData.TakeRecord(id: $0.id, recipeId: $0.recipeId, recipeName: $0.recipeName, rating: $0.rating,
                                  notes: $0.notes, updatedAt: $0.updatedAt)
        }
        var photoDescriptor = FetchDescriptor<RecipePhoto>()
        photoDescriptor.propertiesToFetch = [\.id, \.recipeId, \.dateAdded]
        let photos = try context.fetch(photoDescriptor).map {
            BackupData.PhotoRecord(id: $0.id, recipeId: $0.recipeId, dateAdded: $0.dateAdded, file: BackupFormat.photoPath($0.id))
        }

        return BackupData(
            cabinetItems: cabinet.sorted { ($0.dateAdded, $0.id.uuidString) < ($1.dateAdded, $1.id.uuidString) },
            favourites: favourites.sorted { ($0.dateFavourited, $0.id.uuidString) < ($1.dateFavourited, $1.id.uuidString) },
            shoppingItems: shopping.sorted { ($0.dateAdded, $0.id.uuidString) < ($1.dateAdded, $1.id.uuidString) },
            takes: takes.sorted { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) },
            photos: photos.sorted { ($0.dateAdded, $0.id.uuidString) < ($1.dateAdded, $1.id.uuidString) },
            preferences: .init(
                tasteProfile: TasteProfileStore.load(defaults: defaults),
                pantryStaples: PantryStore.load(defaults: defaults).map(\.rawValue).sorted()))
    }

    private struct MissingPhoto: Error {}

    /// Fetched on its own so only this photo's full image is loaded.
    private static func fullImage(_ id: UUID, context: ModelContext) throws -> Data {
        var descriptor = FetchDescriptor<RecipePhoto>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let photo = try context.fetch(descriptor).first else { throw MissingPhoto() }
        return photo.full
    }

    private static func add(_ data: Data, path: String, compressed: Bool, to archive: Archive, date: Date) throws {
        try archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count), modificationDate: date,
            compressionMethod: compressed ? .deflate : .none
        ) { position, size in
            let start = Int(position)
            return data.subdata(in: start..<start + size)
        }
    }
}
