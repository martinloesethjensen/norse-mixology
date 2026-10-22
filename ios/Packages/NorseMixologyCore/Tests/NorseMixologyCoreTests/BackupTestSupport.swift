import Foundation
import SwiftData
@testable import NorseMixologyCore

/// On-disk stores and hand-made archives for the backup tests. On-disk (not
/// in-memory) because the writer reads through its own `ModelContext`s.
final class BackupTestStore {
    let directory: URL
    let container: ModelContainer

    static let schema = Schema([CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self, RecipeTake.self, RecipePhoto.self])

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: Self.schema, url: directory.appendingPathComponent("store.sqlite"))
        container = try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A scratch folder inside this store's directory, removed with it.
    func scratch(_ name: String = UUID().uuidString) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum BackupFixtures {
    static let flavor = FlavorProfile(sweetness: 0.1, bitterness: 0.8, smokiness: 0, citrus: 0.2, floral: 0, spice: 0.1,
                                      herbal: 0.6, fruity: 0, oaky: 0, abv: 25)
    /// Real JPEGs, because the reader decodes every photo; different sizes, so their bytes differ.
    static let photoBytes: [(full: Data, thumbnail: Data)] = [
        (TestImages.jpeg(width: 64, height: 48), TestImages.jpeg(width: 32, height: 24)),
        (TestImages.jpeg(width: 80, height: 60), TestImages.jpeg(width: 40, height: 30)),
    ]
    static let otherPhoto = (full: TestImages.jpeg(width: 48, height: 48), thumbnail: TestImages.jpeg(width: 24, height: 24))

    /// Whole seconds, so dates survive the millisecond JSON format exactly.
    static func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_760_000_000 + seconds) }

    static func cabinetItem(styleId: UUID = UUID(), name: String = "Campari", brand: String? = nil) -> CabinetItem {
        CabinetItem(ingredientStyleId: styleId, ingredientFamilyId: UUID(), categoryId: UUID(), displayName: name, brand: brand,
                    style: name, family: "Bitter Aperitif", category: "Liqueur", flavorProfile: flavor, dateAdded: date(1))
    }

    /// Fills a store with one of everything, two photos on one recipe.
    @discardableResult
    static func populate(_ context: ModelContext) throws -> (recipeId: UUID, photoIds: [UUID]) {
        let recipeId = UUID()
        context.insert(cabinetItem(name: "Campari", brand: "Campari"))
        context.insert(cabinetItem(name: "Gin"))
        context.insert(FavouriteRecipe(recipeId: recipeId, recipeName: "Negroni", dateFavourited: date(2)))
        context.insert(ShoppingItem(ingredientStyleId: UUID(), styleName: "Sweet Vermouth", dateAdded: date(3)))
        context.insert(RecipeTake(recipeId: recipeId, recipeName: "Negroni", rating: 5, notes: "Orange peel.", updatedAt: date(4)))
        let first = RecipePhoto(recipeId: recipeId, thumbnail: photoBytes[0].thumbnail, full: photoBytes[0].full,
                                dateAdded: date(5))
        let second = RecipePhoto(recipeId: recipeId, thumbnail: photoBytes[1].thumbnail, full: photoBytes[1].full,
                                 dateAdded: date(6))
        context.insert(first)
        context.insert(second)
        try context.save()
        return (recipeId, [first.id, second.id])
    }

    /// Packs a hand-made folder (`manifest.json` plus files) into an archive.
    static func archive(manifest: Data?, files: [String: Data] = [:], in folder: URL) throws -> URL {
        let staging = folder.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging.appendingPathComponent("photos"), withIntermediateDirectories: true)
        if let manifest { try manifest.write(to: staging.appendingPathComponent(BackupManifest.fileName)) }
        for (path, data) in files { try data.write(to: staging.appendingPathComponent(path)) }
        let archive = folder.appendingPathComponent("hand-made-\(UUID().uuidString).nmbackup")
        try BackupArchive.pack(directory: staging, into: archive)
        return archive
    }

    /// A valid manifest with one take and one photo, plus the photo files it names.
    static func validManifest(photoId: UUID = UUID(), recipeId: UUID = UUID(), rating: Double = 4, notes: String = "Nice")
        -> (manifest: BackupManifest, files: [String: Data]) {
        let paths = PhotoRecord.paths(for: photoId)
        let manifest = BackupManifest(
            appVersion: "1.0", createdAt: date(100),
            takes: [TakeRecord(id: UUID(), recipeId: recipeId, recipeName: "Daiquiri", rating: rating, notes: notes, updatedAt: date(10))],
            photos: [PhotoRecord(id: photoId, recipeId: recipeId, dateAdded: date(11), fullFile: paths.full, thumbnailFile: paths.thumbnail)])
        return (manifest, [paths.full: otherPhoto.full, paths.thumbnail: otherPhoto.thumbnail])
    }

    static func encoded(_ manifest: BackupManifest) throws -> Data { try BackupJSON.encoder().encode(manifest) }
}
