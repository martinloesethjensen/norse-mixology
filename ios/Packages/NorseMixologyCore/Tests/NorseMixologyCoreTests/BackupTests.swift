import XCTest
import SwiftData
import ZIPFoundation
@testable import NorseMixologyCore

/// Backup spec §3, §5 and §6: a round trip keeps everything, a bad file is
/// refused before anything is touched, and a failed restore changes nothing.
final class BackupTests: XCTestCase {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private static let schema = Schema([CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self, RecipeTake.self, RecipePhoto.self])
    // Whole seconds, so dates compare exactly after the JSON round trip.
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let sourceSuite = "BackupTests.source"
    private let targetSuite = "BackupTests.target"
    private var source: UserDefaults!
    private var target: UserDefaults!
    private var workDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        source = UserDefaults(suiteName: sourceSuite)
        target = UserDefaults(suiteName: targetSuite)
        source.removePersistentDomain(forName: sourceSuite)
        target.removePersistentDomain(forName: targetSuite)
        workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        source.removePersistentDomain(forName: sourceSuite)
        target.removePersistentDomain(forName: targetSuite)
        try? FileManager.default.removeItem(at: workDirectory)
        try super.tearDownWithError()
    }

    private func makeStore() throws -> Store {
        let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        return Store(container: container, context: ModelContext(container))
    }

    private var extractDirectory: URL { workDirectory.appendingPathComponent("extract") }
    private var backupURL: URL { workDirectory.appendingPathComponent("test.norsebackup") }

    private let campari = FlavorProfile(sweetness: 0.5, bitterness: 0.9, smokiness: 0, citrus: 0.4, floral: 0.1,
                                        spice: 0.2, herbal: 0.6, fruity: 0.3, oaky: 0, abv: 0.25)

    /// One of everything, a take for a recipe no catalog has, and two photos. Returns the full photo bytes.
    @discardableResult
    private func populate(_ context: ModelContext, defaults: UserDefaults) throws -> [UUID: Data] {
        let negroni = UUID()
        context.insert(CabinetItem(ingredientStyleId: UUID(), ingredientFamilyId: UUID(), categoryId: UUID(),
                                   displayName: "Campari", brand: "Campari", style: "Campari", family: "Red Bitter Aperitivo",
                                   category: "Liqueurs", flavorProfile: campari, dateAdded: t0))
        context.insert(CabinetItem(ingredientStyleId: UUID(), ingredientFamilyId: UUID(), categoryId: UUID(),
                                   displayName: "London Dry Gin", brand: nil, style: "London Dry Gin", family: "Gin",
                                   category: "Spirits", flavorProfile: campari, dateAdded: t0 + 1))
        context.insert(FavouriteRecipe(recipeId: negroni, recipeName: "Negroni", dateFavourited: t0 + 60))
        context.insert(ShoppingItem(ingredientStyleId: UUID(), styleName: "Sweet Vermouth", dateAdded: t0 + 120))
        context.insert(RecipeTake(recipeId: negroni, recipeName: "Negroni", rating: 4, notes: "Stir longer.", updatedAt: t0 + 180))
        context.insert(RecipeTake(recipeId: UUID(), recipeName: "A Recipe The Catalog Dropped", notes: "Still mine.", updatedAt: t0 + 240))

        var fulls: [UUID: Data] = [:]
        for index in 0..<2 {
            let processed = try PhotoProcessor.process(TestImages.jpeg(width: 400 + index * 100, height: 300))
            let photo = RecipePhoto(recipeId: negroni, thumbnail: processed.thumbnail, full: processed.full,
                                    dateAdded: t0 + Double(200 + index))
            context.insert(photo)
            fulls[photo.id] = processed.full
        }
        try context.save()

        TasteProfileStore.save(UserTasteProfile(sweetness: 0.2, bitterness: 0.9, citrus: 0.4, smokiness: 0.1, herbal: 0.7,
                                                hasCompletedOnboarding: true), defaults: defaults)
        PantryStore.save([.sugar, .eggs], defaults: defaults)
        return fulls
    }

    @discardableResult
    private func export(_ context: ModelContext, defaults: UserDefaults) throws -> BackupManifest {
        try BackupExporter.export(context: context, defaults: defaults, catalogContentVersion: "48c3086b",
                                  appVersion: "1.0 (1)", to: backupURL, now: t0 + 3_600)
    }

    // MARK: - Crafted archives

    private struct Entry {
        var path: String
        var data: Data
    }

    private func write(_ entries: [Entry], compressJSON: Bool = true) throws -> URL {
        let url = backupURL
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(with: entry.path, type: .file, uncompressedSize: Int64(entry.data.count),
                                 compressionMethod: compressJSON && entry.path.hasSuffix(".json") ? .deflate : .none) { position, size in
                entry.data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    private func manifest(for data: BackupData, format: String = BackupFormat.identifier, version: Int = 1) -> BackupManifest {
        BackupManifest(format: format, formatVersion: version, createdAt: t0, appVersion: "1.0 (1)",
                       catalogContentVersion: nil, counts: data.counts)
    }

    private func entries(_ data: BackupData, manifest: BackupManifest? = nil, photos: [UUID: Data] = [:]) throws -> [Entry] {
        let encoder = BackupFormat.encoder()
        return [
            Entry(path: "manifest.json", data: try encoder.encode(manifest ?? self.manifest(for: data))),
            Entry(path: "data.json", data: try encoder.encode(data)),
        ] + photos.map { Entry(path: BackupFormat.photoPath($0.key), data: $0.value) }
    }

    private func emptyData() -> BackupData {
        BackupData(cabinetItems: [], favourites: [], shoppingItems: [], takes: [], photos: [],
                   preferences: .init(tasteProfile: .neutral, pantryStaples: []))
    }

    private func take(_ recipeId: UUID, rating: Int = 3, notes: String = "") -> BackupData.TakeRecord {
        .init(id: UUID(), recipeId: recipeId, recipeName: "Negroni", rating: rating, notes: notes, updatedAt: t0)
    }

    private func photo(_ recipeId: UUID, at offset: TimeInterval = 0) -> BackupData.PhotoRecord {
        let id = UUID()
        return .init(id: id, recipeId: recipeId, dateAdded: t0 + offset, file: BackupFormat.photoPath(id))
    }

    /// Data with one take and one real photo, plus the photo bytes to put in the archive.
    private func dataWithPhoto() -> (BackupData, [UUID: Data]) {
        let recipeId = UUID()
        let record = photo(recipeId)
        var data = emptyData()
        data.takes = [take(recipeId)]
        data.photos = [record]
        return (data, [record.id: TestImages.jpeg(width: 120, height: 90)])
    }

    private func assertRead(_ url: URL, throws expected: BackupError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BackupReader.read(url, into: extractDirectory), file: file, line: line) {
            XCTAssertEqual($0 as? BackupError, expected, file: file, line: line)
        }
    }

    private func assertDamaged(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BackupReader.read(url, into: extractDirectory), file: file, line: line) {
            guard case .damaged = $0 as? BackupError else {
                return XCTFail("expected damaged, got \($0)", file: file, line: line)
            }
        }
    }

    private func assertValidationDamaged(_ data: BackupData, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BackupReader.validated(data), file: file, line: line) {
            guard case .damaged = $0 as? BackupError else {
                return XCTFail("expected damaged, got \($0)", file: file, line: line)
            }
        }
    }

    // MARK: - Round trip

    func testRoundTripRestoresEverything() throws {
        let original = try makeStore()
        let fulls = try populate(original.context, defaults: source)
        try export(original.context, defaults: source)

        let restored = try makeStore()
        let contents = try BackupReader.read(backupURL, into: extractDirectory)
        try BackupRestorer.restore(contents, context: restored.context, defaults: target)

        let before = try BackupExporter.snapshot(context: original.context, defaults: source)
        let after = try BackupExporter.snapshot(context: ModelContext(restored.container), defaults: target)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.takes.count, 2, "the take for a recipe no catalog has is kept")
        XCTAssertNil(after.cabinetItems.first { $0.displayName == "London Dry Gin" }?.brand)

        for (id, full) in fulls {
            let photo = try XCTUnwrap(RecipeTakeService.photo(id: id, context: restored.context))
            XCTAssertEqual(photo.full, full, "a JPEG within the cap is restored byte for byte, not recompressed")
            let thumbnail = try XCTUnwrap(TestImages.pixelSize(of: photo.thumbnail))
            XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), TakeLimits.thumbnailMaxPixels)
        }
    }

    func testManifestDescribesTheExport() throws {
        let store = try makeStore()
        try populate(store.context, defaults: source)
        let written = try export(store.context, defaults: source)

        XCTAssertEqual(written.counts, .init(cabinetItems: 2, favourites: 1, shoppingItems: 1, takes: 2, photos: 2))
        XCTAssertEqual(written.format, BackupFormat.identifier)
        XCTAssertEqual(written.formatVersion, 1)
        XCTAssertEqual(written.catalogContentVersion, "48c3086b")
        XCTAssertEqual(try BackupReader.readManifest(backupURL), written)
    }

    func testEmptyExportRestoresToAnEmptyApp() throws {
        try export(try makeStore().context, defaults: source)

        let store = try makeStore()
        try populate(store.context, defaults: target)
        try BackupRestorer.restore(try BackupReader.read(backupURL, into: extractDirectory), context: store.context, defaults: target)

        XCTAssertEqual(try BackupExporter.snapshot(context: ModelContext(store.container), defaults: target), emptyData())
        XCTAssertEqual(TasteProfileStore.load(defaults: target), .neutral)
        XCTAssertTrue(PantryStore.load(defaults: target).isEmpty)
    }

    func testExportReplacesAnExistingFile() throws {
        try Data("old".utf8).write(to: backupURL)
        try export(try makeStore().context, defaults: source)
        XCTAssertNoThrow(try BackupReader.readManifest(backupURL))
    }

    func testFailedExportLeavesNoFile() throws {
        let url = workDirectory.appendingPathComponent("missing-folder/test.norsebackup")
        XCTAssertThrowsError(try BackupExporter.export(context: try makeStore().context, defaults: source,
                                                       catalogContentVersion: nil, appVersion: "1.0", to: url)) {
            XCTAssertEqual($0 as? BackupError, .writeFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Not a backup / format

    func testAFileThatIsNotAZipIsNotABackup() throws {
        try Data("just some text".utf8).write(to: backupURL)
        assertRead(backupURL, throws: .notABackup)
        XCTAssertThrowsError(try BackupReader.readManifest(backupURL)) { XCTAssertEqual($0 as? BackupError, .notABackup) }
    }

    func testAZipWithoutAManifestIsNotABackup() throws {
        assertRead(try write([Entry(path: "data.json", data: try BackupFormat.encoder().encode(emptyData()))]), throws: .notABackup)
    }

    func testAnotherAppsManifestIsNotABackup() throws {
        let data = emptyData()
        assertRead(try write(entries(data, manifest: manifest(for: data, format: "com.example.other"))), throws: .notABackup)
    }

    func testANewerFormatIsRefused() throws {
        let data = emptyData()
        let url = try write(entries(data, manifest: manifest(for: data, version: 2)))
        assertRead(url, throws: .newerFormat(2))
        XCTAssertThrowsError(try BackupReader.readManifest(url)) { XCTAssertEqual($0 as? BackupError, .newerFormat(2)) }
    }

    // MARK: - Damaged

    func testATruncatedFileIsDamaged() throws {
        let store = try makeStore()
        try populate(store.context, defaults: source)
        try export(store.context, defaults: source)
        let bytes = try Data(contentsOf: backupURL)
        try bytes.prefix(bytes.count / 2).write(to: backupURL)

        assertDamaged(backupURL)
    }

    func testACorruptEntryIsDamaged() throws {
        var data = emptyData()
        data.favourites = [.init(id: UUID(), recipeId: UUID(), recipeName: "Negroni", dateFavourited: t0)]
        // Stored rather than deflated, so the name can be found and changed under its checksum.
        let url = try write(entries(data), compressJSON: false)
        var bytes = try Data(contentsOf: url)
        let range = try XCTUnwrap(bytes.range(of: Data("Negroni".utf8)))
        bytes[range.upperBound - 1] = UInt8(ascii: "j")
        try bytes.write(to: url)

        assertDamaged(url)
    }

    func testDuplicateIdsAreDamaged() throws {
        var data = emptyData()
        let favourite = BackupData.FavouriteRecord(id: UUID(), recipeId: UUID(), recipeName: "Negroni", dateFavourited: t0)
        data.favourites = [favourite, favourite]
        assertDamaged(try write(entries(data)))
    }

    func testCountsThatDontMatchAreDamaged() throws {
        let data = emptyData()
        var lying = manifest(for: data)
        lying.counts.cabinetItems = 3
        assertDamaged(try write(entries(data, manifest: lying)))
    }

    func testAMissingPhotoIsDamaged() throws {
        let (data, _) = dataWithPhoto()
        assertDamaged(try write(entries(data)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: extractDirectory.path), [], "nothing left behind")
    }

    func testAPhotoThatIsNotAnImageIsUnreadable() throws {
        let (data, photos) = dataWithPhoto()
        let id = try XCTUnwrap(photos.keys.first)
        assertRead(try write(entries(data, photos: [id: Data("not a jpeg".utf8)])), throws: .photoUnreadable(id))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: extractDirectory.path), [], "nothing left behind")
    }

    // MARK: - Untrusted-file guards

    func testAPhotoPathOutsidePhotosIsRefused() throws {
        let (original, photos) = dataWithPhoto()
        var data = original
        data.photos[0].file = "../escape.jpg"
        assertDamaged(try write(entries(data, photos: photos) + [Entry(path: "../escape.jpg", data: photos.first!.value)]))
    }

    func testUnexpectedEntriesAreIgnored() throws {
        let (data, photos) = dataWithPhoto()
        let extras = [Entry(path: "../outside.txt", data: Data("x".utf8)), Entry(path: "photos/extra.jpg", data: Data("y".utf8))]
        let contents = try BackupReader.read(try write(entries(data, photos: photos) + extras), into: extractDirectory)

        XCTAssertEqual(contents.photoFiles.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDirectory.deletingLastPathComponent()
            .appendingPathComponent("outside.txt").path))
        let written = try FileManager.default.subpathsOfDirectory(atPath: contents.directory.path)
        XCTAssertEqual(Set(written), Set(contents.photoFiles.values.flatMap { [$0.full.lastPathComponent, $0.thumbnail.lastPathComponent] }))
    }

    func testAnEntryOverItsCapIsTooLarge() throws {
        let url = try write(entries(emptyData()))
        var limits = BackupReader.Limits.default
        limits.dataBytes = 64
        XCTAssertThrowsError(try BackupReader.read(url, into: extractDirectory, limits: limits)) {
            XCTAssertEqual($0 as? BackupError, .tooLarge)
        }
    }

    func testAnArchiveOverTheTotalCapIsTooLarge() throws {
        let (data, photos) = dataWithPhoto()
        let all = try entries(data, photos: photos)
        let url = try write(all)
        var limits = BackupReader.Limits.default
        // Room for the JSON, not the photo.
        limits.totalBytes = all.filter { $0.path.hasSuffix(".json") }.map(\.data.count).reduce(0, +) + 10
        XCTAssertThrowsError(try BackupReader.read(url, into: extractDirectory, limits: limits)) {
            XCTAssertEqual($0 as? BackupError, .tooLarge)
        }
    }

    // MARK: - Validation and normalisation

    func testValuesTheAppCouldNeverWriteAreDamaged() {
        let recipeId = UUID()

        var rating = emptyData()
        rating.takes = [take(recipeId, rating: 7)]
        assertValidationDamaged(rating)

        var flavour = emptyData()
        var profile = campari
        profile.bitterness = 1.5
        flavour.cabinetItems = [.init(id: UUID(), ingredientStyleId: UUID(), ingredientFamilyId: UUID(), categoryId: UUID(),
                                      displayName: "Campari", brand: nil, style: "Campari", family: "Bitter",
                                      category: "Liqueurs", flavorProfile: profile, dateAdded: t0)]
        assertValidationDamaged(flavour)

        var taste = emptyData()
        taste.preferences.tasteProfile.citrus = -0.1
        assertValidationDamaged(taste)

        var orphan = emptyData()
        orphan.photos = [photo(recipeId)]
        assertValidationDamaged(orphan)

        var twoTakes = emptyData()
        twoTakes.takes = [take(recipeId), take(recipeId)]
        assertValidationDamaged(twoTakes)
    }

    func testNotesAndPhotosAreLimitedAsTypingWould() throws {
        let recipeId = UUID()
        let emptyRecipe = UUID()
        var data = emptyData()
        data.takes = [take(recipeId, rating: 0, notes: String(repeating: "a", count: 2_500)),
                      take(emptyRecipe, rating: 0, notes: "   \n")]
        // Newest first, so the kept ones are a choice, not the input order.
        data.photos = (0..<8).reversed().map { photo(recipeId, at: Double($0)) }

        let result = try BackupReader.validated(data)

        XCTAssertEqual(result.takes.map(\.recipeId), [recipeId], "a take left empty doesn't exist")
        XCTAssertEqual(result.takes.first?.notes.count, TakeLimits.maxNotesLength)
        XCTAssertEqual(result.photos.map(\.dateAdded), (0..<6).map { t0 + Double($0) }, "the oldest six are kept")
    }

    func testOnlyKeptPhotosAreExtracted() throws {
        let recipeId = UUID()
        var data = emptyData()
        data.takes = [take(recipeId)]
        data.photos = (0..<7).map { photo(recipeId, at: Double($0)) }
        var photos: [UUID: Data] = [:]
        for record in data.photos.dropLast() { photos[record.id] = TestImages.jpeg(width: 40, height: 30) }
        photos[data.photos.last!.id] = Data("never read".utf8)

        let contents = try BackupReader.read(try write(entries(data, photos: photos)), into: extractDirectory)
        XCTAssertEqual(contents.photoFiles.count, TakeLimits.maxPhotos)
        XCTAssertEqual(contents.manifest.counts.photos, 7, "the manifest is as written")
    }

    func testAnOversizedPhotoIsCappedOnRestore() throws {
        let (processedFull, _) = try PhotoProcessor.processRestored(TestImages.jpeg(width: 2_000, height: 1_000))
        let size = try XCTUnwrap(TestImages.pixelSize(of: processedFull))
        XCTAssertEqual(max(size.width, size.height), TakeLimits.fullPhotoMaxPixels)

        let small = TestImages.jpeg(width: 300, height: 200)
        XCTAssertEqual(try PhotoProcessor.processRestored(small).full, small)
        XCTAssertThrowsError(try PhotoProcessor.processRestored(Data("junk".utf8)))
    }

    // MARK: - Restore

    func testRestoreReplacesEverythingAlreadyThere() throws {
        let backup = try makeStore()
        backup.context.insert(FavouriteRecipe(recipeId: UUID(), recipeName: "Paper Plane", dateFavourited: t0))
        try backup.context.save()
        try export(backup.context, defaults: source)

        let store = try makeStore()
        try populate(store.context, defaults: target)
        try BackupRestorer.restore(try BackupReader.read(backupURL, into: extractDirectory), context: store.context, defaults: target)

        let after = try BackupExporter.snapshot(context: ModelContext(store.container), defaults: target)
        XCTAssertEqual(after.favourites.map(\.recipeName), ["Paper Plane"])
        XCTAssertTrue(after.cabinetItems.isEmpty && after.shoppingItems.isEmpty && after.takes.isEmpty && after.photos.isEmpty)
    }

    func testAFailedSaveLeavesTheStoreAndPreferencesUnchanged() throws {
        let other = try makeStore()
        other.context.insert(FavouriteRecipe(recipeId: UUID(), recipeName: "Paper Plane", dateFavourited: t0))
        try other.context.save()
        try export(other.context, defaults: source)
        let contents = try BackupReader.read(backupURL, into: extractDirectory)

        let store = try makeStore()
        try populate(store.context, defaults: target)
        let before = try BackupExporter.snapshot(context: store.context, defaults: target)
        let autosave = store.context.autosaveEnabled

        struct DiskFull: Error {}
        XCTAssertThrowsError(try BackupRestorer.restore(contents, context: store.context, defaults: target) { _ in throw DiskFull() }) {
            XCTAssertEqual($0 as? BackupError, .saveFailed)
        }

        XCTAssertEqual(try BackupExporter.snapshot(context: store.context, defaults: target), before)
        XCTAssertEqual(try BackupExporter.snapshot(context: ModelContext(store.container), defaults: target), before)
        XCTAssertEqual(store.context.autosaveEnabled, autosave)
    }

    func testUnknownPantryStaplesAreDropped() throws {
        var data = emptyData()
        data.preferences.pantryStaples = ["sugar", "caviar"]
        let contents = try BackupReader.read(try write(entries(data)), into: extractDirectory)
        try BackupRestorer.restore(contents, context: try makeStore().context, defaults: target)
        XCTAssertEqual(PantryStore.load(defaults: target), [.sugar])
    }

    // MARK: - Version 1 fixture

    /// A committed file written to the version 1 format. If this breaks, old backups no longer restore.
    func testTheVersion1FixtureStillRestores() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "backup-v1", withExtension: "norsebackup"))
        let manifest = try BackupReader.readManifest(url)
        XCTAssertEqual(manifest.counts, .init(cabinetItems: 1, favourites: 1, shoppingItems: 1, takes: 1, photos: 2))
        XCTAssertEqual(manifest.catalogContentVersion, "48c3086b")

        let store = try makeStore()
        try BackupRestorer.restore(try BackupReader.read(url, into: extractDirectory), context: store.context, defaults: target)
        let restored = try BackupExporter.snapshot(context: ModelContext(store.container), defaults: target)

        let campari = try XCTUnwrap(restored.cabinetItems.first)
        XCTAssertEqual(campari.displayName, "Campari")
        XCTAssertEqual(campari.flavorProfile.bitterness, 0.9)
        XCTAssertEqual(campari.dateAdded, ISO8601DateFormatter().date(from: "2026-09-01T18:00:00Z"))
        XCTAssertEqual(restored.favourites.first?.recipeName, "Negroni")
        XCTAssertEqual(try XCTUnwrap(restored.favourites.first?.dateFavourited.timeIntervalSince1970),
                       try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-02T19:30:00Z")).timeIntervalSince1970 + 0.25,
                       accuracy: 0.001)
        XCTAssertEqual(restored.shoppingItems.first?.styleName, "Sweet Vermouth")
        XCTAssertEqual(restored.takes.first?.rating, 4)
        XCTAssertEqual(restored.takes.first?.notes, "Stir longer. Orange twist, not lemon.")
        XCTAssertEqual(restored.photos.count, 2)
        for record in restored.photos {
            let photo = try XCTUnwrap(RecipeTakeService.photo(id: record.id, context: store.context))
            XCTAssertNotNil(TestImages.pixelSize(of: photo.full))
            XCTAssertNotNil(TestImages.pixelSize(of: photo.thumbnail))
        }
        XCTAssertEqual(TasteProfileStore.load(defaults: target).bitterness, 0.8)
        XCTAssertTrue(TasteProfileStore.load(defaults: target).hasCompletedOnboarding)
        XCTAssertEqual(PantryStore.load(defaults: target), [.sugar, .lemonsAndLimes])
    }
}
