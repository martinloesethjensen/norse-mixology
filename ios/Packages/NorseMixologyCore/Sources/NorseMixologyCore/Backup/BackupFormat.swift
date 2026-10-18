import Foundation

/// Version 1 of the `.norsebackup` file: a ZIP holding `manifest.json`,
/// `data.json` and `photos/<id>.jpg` (Backup spec §2).
public enum BackupFormat {
    public static let identifier = "dev.martinloeseth.norsemixology.backup"
    public static let version = 1
    public static let fileExtension = "norsebackup"

    static let manifestPath = "manifest.json"
    static let dataPath = "data.json"

    static func photoPath(_ id: UUID) -> String { "photos/\(id.uuidString).jpg" }

    /// ISO 8601 with fractional seconds, so dates survive a round trip exactly.
    /// Reading also accepts whole seconds.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter().string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = fractionalFormatter().date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

/// Read first, and enough for the restore confirmation.
public struct BackupManifest: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var cabinetItems: Int
        public var favourites: Int
        public var shoppingItems: Int
        public var takes: Int
        public var photos: Int

        public init(cabinetItems: Int, favourites: Int, shoppingItems: Int, takes: Int, photos: Int) {
            self.cabinetItems = cabinetItems
            self.favourites = favourites
            self.shoppingItems = shoppingItems
            self.takes = takes
            self.photos = photos
        }
    }

    public var format: String
    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String
    public var catalogContentVersion: String?
    public var counts: Counts
}

/// Plain copies of the SwiftData models, decoupled from the `@Model` classes so a
/// schema change can keep reading version 1. Unknown keys are ignored when decoding.
public struct BackupData: Codable, Equatable, Sendable {
    public struct CabinetItemRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var ingredientStyleId: UUID
        public var ingredientFamilyId: UUID
        public var categoryId: UUID
        public var displayName: String
        public var brand: String?
        public var style: String
        public var family: String
        public var category: String
        public var flavorProfile: FlavorProfile
        public var dateAdded: Date
    }

    public struct FavouriteRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var recipeId: UUID
        public var recipeName: String
        public var dateFavourited: Date
    }

    public struct ShoppingItemRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var ingredientStyleId: UUID
        public var styleName: String
        public var dateAdded: Date
    }

    public struct TakeRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var recipeId: UUID
        public var recipeName: String
        public var rating: Int
        public var notes: String
        public var updatedAt: Date
    }

    public struct PhotoRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var recipeId: UUID
        public var dateAdded: Date
        public var file: String
    }

    public struct Preferences: Codable, Equatable, Sendable {
        public var tasteProfile: UserTasteProfile
        /// `PantryStaple` raw values; unknown ones are dropped on restore.
        public var pantryStaples: [String]
    }

    public var cabinetItems: [CabinetItemRecord]
    public var favourites: [FavouriteRecord]
    public var shoppingItems: [ShoppingItemRecord]
    public var takes: [TakeRecord]
    public var photos: [PhotoRecord]
    public var preferences: Preferences

    var counts: BackupManifest.Counts {
        .init(cabinetItems: cabinetItems.count, favourites: favourites.count, shoppingItems: shoppingItems.count,
              takes: takes.count, photos: photos.count)
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// Not a ZIP, or no Norse Mixology manifest.
    case notABackup
    /// Made by a newer version of the app.
    case newerFormat(Int)
    /// Readable as a backup but inconsistent or corrupt; the reason is for logs, not users.
    case damaged(String)
    /// An entry, or the whole archive, is over its size cap.
    case tooLarge
    /// A photo in the backup isn't a readable image.
    case photoUnreadable(UUID)
    /// Writing the backup file failed (for example, the disk is full).
    case writeFailed
    /// The restore couldn't be saved; nothing was changed.
    case saveFailed
}
