import Foundation

/// The contents of `manifest.json` inside a `.nmbackup` file (Backup spec §2).
/// Ids are kept as they are, so a restore can recognise what it already has.
/// Unknown keys are ignored when decoding, so additive fields stay readable.
public struct BackupManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let fileName = "manifest.json"

    public var formatVersion: Int
    public var appVersion: String
    public var createdAt: Date
    public var cabinet: [CabinetRecord]
    public var favourites: [FavouriteRecord]
    public var shopping: [ShoppingRecord]
    public var takes: [TakeRecord]
    public var photos: [PhotoRecord]

    public init(formatVersion: Int = BackupManifest.currentFormatVersion, appVersion: String, createdAt: Date,
                cabinet: [CabinetRecord] = [], favourites: [FavouriteRecord] = [], shopping: [ShoppingRecord] = [],
                takes: [TakeRecord] = [], photos: [PhotoRecord] = []) {
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.cabinet = cabinet
        self.favourites = favourites
        self.shopping = shopping
        self.takes = takes
        self.photos = photos
    }
}

public struct CabinetRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var ingredientStyleId: UUID
    public var ingredientFamilyId: UUID
    public var categoryId: UUID
    public var displayName: String
    public var brand: String?
    public var style: String
    public var family: String
    public var category: String
    public var flavor: FlavorProfile
    public var dateAdded: Date
}

public struct FavouriteRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var recipeId: UUID
    public var recipeName: String
    public var dateFavourited: Date
}

public struct ShoppingRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var ingredientStyleId: UUID
    public var styleName: String
    public var dateAdded: Date
}

public struct TakeRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var recipeId: UUID
    public var recipeName: String
    public var rating: Double
    public var notes: String
    public var updatedAt: Date
}

public struct PhotoRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var recipeId: UUID
    public var dateAdded: Date
    /// Archive-relative path, e.g. `photos/<id>.jpg`.
    public var fullFile: String
    /// Archive-relative path, e.g. `photos/<id>-thumb.jpg`.
    public var thumbnailFile: String

    public static func paths(for id: UUID) -> (full: String, thumbnail: String) {
        ("photos/\(id.uuidString).jpg", "photos/\(id.uuidString)-thumb.jpg")
    }
}

// MARK: - Model ↔ record

extension CabinetRecord {
    public init(_ item: CabinetItem) {
        self.init(id: item.id, ingredientStyleId: item.ingredientStyleId, ingredientFamilyId: item.ingredientFamilyId,
                  categoryId: item.categoryId, displayName: item.displayName, brand: item.brand, style: item.style,
                  family: item.family, category: item.category, flavor: item.flavorProfile, dateAdded: item.dateAdded)
    }

    public func makeModel() -> CabinetItem {
        CabinetItem(id: id, ingredientStyleId: ingredientStyleId, ingredientFamilyId: ingredientFamilyId, categoryId: categoryId,
                    displayName: displayName, brand: brand, style: style, family: family, category: category,
                    flavorProfile: flavor, dateAdded: dateAdded)
    }
}

extension FavouriteRecord {
    public init(_ favourite: FavouriteRecipe) {
        self.init(id: favourite.id, recipeId: favourite.recipeId, recipeName: favourite.recipeName,
                  dateFavourited: favourite.dateFavourited)
    }

    public func makeModel() -> FavouriteRecipe {
        FavouriteRecipe(id: id, recipeId: recipeId, recipeName: recipeName, dateFavourited: dateFavourited)
    }
}

extension ShoppingRecord {
    public init(_ item: ShoppingItem) {
        self.init(id: item.id, ingredientStyleId: item.ingredientStyleId, styleName: item.styleName, dateAdded: item.dateAdded)
    }

    public func makeModel() -> ShoppingItem {
        ShoppingItem(id: id, ingredientStyleId: ingredientStyleId, styleName: styleName, dateAdded: dateAdded)
    }
}

extension TakeRecord {
    public init(_ take: RecipeTake) {
        self.init(id: take.id, recipeId: take.recipeId, recipeName: take.recipeName, rating: take.rating,
                  notes: take.notes, updatedAt: take.updatedAt)
    }

    public func makeModel() -> RecipeTake {
        RecipeTake(id: id, recipeId: recipeId, recipeName: recipeName, rating: rating, notes: notes, updatedAt: updatedAt)
    }
}

// MARK: - JSON

/// JSON coding for the manifest: ISO-8601 dates with milliseconds, stable key order.
enum BackupJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter().string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = formatter().date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
            }
            return date
        }
        return decoder
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
