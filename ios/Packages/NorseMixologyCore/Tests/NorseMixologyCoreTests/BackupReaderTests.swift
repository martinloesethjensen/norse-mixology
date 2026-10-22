import XCTest
@testable import NorseMixologyCore

/// Backup spec §3/§5: every bad file is refused before the store is touched,
/// and the temporary folder never outlives the reader.
final class BackupReaderTests: XCTestCase {
    private func assertRefused(_ archive: URL, as expected: BackupError, in store: BackupTestStore,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let temporary = try store.scratch()
        XCTAssertThrowsError(try BackupReader.open(archive, temporaryDirectory: temporary), file: file, line: line) { error in
            XCTAssertEqual(error as? BackupError, expected, file: file, line: line)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), [],
                       "nothing left behind", file: file, line: line)
    }

    func testAValidBackupOpensWithASummary() throws {
        let store = try BackupTestStore()
        let valid = BackupFixtures.validManifest()
        let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(valid.manifest), files: valid.files, in: try store.scratch())

        let opened = try BackupReader.open(archive, temporaryDirectory: try store.scratch())
        defer { opened.close() }

        XCTAssertEqual(opened.summary, BackupSummary(createdAt: BackupFixtures.date(100), cabinetItems: 0, favourites: 0,
                                                     shoppingItems: 0, takes: 1, photos: 1))
    }

    func testJunkAndArchivesWithoutAManifestAreNotBackups() throws {
        let store = try BackupTestStore()
        let junk = try store.scratch().appendingPathComponent("junk.nmbackup")
        try Data("not an archive".utf8).write(to: junk)
        try assertRefused(junk, as: .notABackup, in: store)

        let noManifest = try BackupFixtures.archive(manifest: nil, files: ["photos/a.jpg": Data([1])], in: try store.scratch())
        try assertRefused(noManifest, as: .notABackup, in: store)
    }

    func testANewerFormatIsReportedAsNewerEvenIfItsShapeChanged() throws {
        let store = try BackupTestStore()
        let archive = try BackupFixtures.archive(manifest: Data(#"{"formatVersion": \#(BackupManifest.currentFormatVersion + 1), "everything": "different"}"#.utf8),
                                                 in: try store.scratch())
        try assertRefused(archive, as: .newerVersion, in: store)
    }

    func testABrokenManifestIsDamaged() throws {
        let store = try BackupTestStore()
        let truncated = try BackupFixtures.archive(manifest: Data(#"{"formatVersion": 1, "appVersion": "#.utf8), in: try store.scratch())
        try assertRefused(truncated, as: .damaged, in: store)
        let versionZero = try BackupFixtures.archive(manifest: Data(#"{"formatVersion": 0}"#.utf8), in: try store.scratch())
        try assertRefused(versionZero, as: .damaged, in: store)
    }

    func testMissingOrEmptyPhotoFilesAreDamaged() throws {
        let store = try BackupTestStore()
        let valid = BackupFixtures.validManifest()
        var missing = valid.files
        missing.removeValue(forKey: valid.manifest.photos[0].fullFile)
        try assertRefused(try BackupFixtures.archive(manifest: BackupFixtures.encoded(valid.manifest), files: missing, in: try store.scratch()),
                          as: .damaged, in: store)

        var empty = valid.files
        empty[valid.manifest.photos[0].thumbnailFile] = Data()
        try assertRefused(try BackupFixtures.archive(manifest: BackupFixtures.encoded(valid.manifest), files: empty, in: try store.scratch()),
                          as: .damaged, in: store)
    }

    func testPathsOutsideThePhotosFolderAreDamaged() throws {
        let store = try BackupTestStore()
        for badPath in ["../outside.jpg", "/etc/hosts", "photos/../../outside.jpg", "manifest.json", ""] {
            var valid = BackupFixtures.validManifest()
            valid.manifest.photos[0].fullFile = badPath
            let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(valid.manifest), files: valid.files, in: try store.scratch())
            try assertRefused(archive, as: .damaged, in: store)
        }
    }

    func testRatingsOutOfRangeAreDamagedAndLongNotesAreTrimmed() throws {
        let store = try BackupTestStore()
        let badRating = BackupFixtures.validManifest(rating: 7)
        try assertRefused(try BackupFixtures.archive(manifest: BackupFixtures.encoded(badRating.manifest), files: badRating.files, in: try store.scratch()),
                          as: .damaged, in: store)

        let longNotes = BackupFixtures.validManifest(notes: String(repeating: "n", count: 2_500))
        let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(longNotes.manifest), files: longNotes.files, in: try store.scratch())
        let opened = try BackupReader.open(archive, temporaryDirectory: try store.scratch())
        defer { opened.close() }
        XCTAssertEqual(opened.manifest.takes[0].notes.count, TakeLimits.maxNotesLength)
    }

    func testHalfStarsOpenAndOtherFractionsAreDamaged() throws {
        let store = try BackupTestStore()
        let halfStar = BackupFixtures.validManifest(rating: 3.5)
        let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(halfStar.manifest), files: halfStar.files, in: try store.scratch())
        let opened = try BackupReader.open(archive, temporaryDirectory: try store.scratch())
        defer { opened.close() }
        XCTAssertEqual(opened.manifest.formatVersion, BackupManifest.currentFormatVersion)
        XCTAssertEqual(opened.manifest.takes[0].rating, 3.5)

        let between = BackupFixtures.validManifest(rating: 3.3)
        try assertRefused(try BackupFixtures.archive(manifest: BackupFixtures.encoded(between.manifest), files: between.files, in: try store.scratch()),
                          as: .damaged, in: store)
    }

    func testClosingRemovesTheTemporaryFolder() throws {
        let store = try BackupTestStore()
        let valid = BackupFixtures.validManifest()
        let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(valid.manifest), files: valid.files, in: try store.scratch())
        let temporary = try store.scratch()

        let opened = try BackupReader.open(archive, temporaryDirectory: temporary)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path).count, 1)
        opened.close()

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), [])
    }

    func testTooLittleFreeSpaceIsOutOfSpace() throws {
        let store = try BackupTestStore()
        let valid = BackupFixtures.validManifest()
        let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(valid.manifest), files: valid.files, in: try store.scratch())
        let temporary = try store.scratch()

        XCTAssertThrowsError(try BackupReader.open(archive, temporaryDirectory: temporary, availableSpace: { _ in 10 })) { error in
            XCTAssertEqual(error as? BackupError, .outOfSpace)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), [])
    }

    // MARK: - Photos and values from an untrusted file

    private func open(_ manifest: BackupManifest, files: [String: Data], in store: BackupTestStore) throws -> OpenedBackup {
        let archive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(manifest), files: files, in: try store.scratch())
        return try BackupReader.open(archive, temporaryDirectory: try store.scratch())
    }

    func testAPhotoThatIsNotAnImageIsDamaged() throws {
        let store = try BackupTestStore()
        let valid = BackupFixtures.validManifest()
        var files = valid.files
        files[valid.manifest.photos[0].fullFile] = Data("not a jpeg".utf8)
        try assertRefused(try BackupFixtures.archive(manifest: BackupFixtures.encoded(valid.manifest), files: files, in: try store.scratch()),
                          as: .damaged, in: store)
    }

    func testABrokenThumbnailIsRebuiltFromTheFullImage() throws {
        let store = try BackupTestStore()
        let valid = BackupFixtures.validManifest()
        let photo = valid.manifest.photos[0]
        var files = valid.files
        files[photo.thumbnailFile] = Data([8, 8])

        let opened = try open(valid.manifest, files: files, in: store)
        defer { opened.close() }

        let thumbnail = try Data(contentsOf: opened.url(for: photo.thumbnailFile))
        XCTAssertNotNil(TestImages.pixelSize(of: thumbnail))
        XCTAssertEqual(try Data(contentsOf: opened.url(for: photo.fullFile)), BackupFixtures.otherPhoto.full, "the full image is untouched")
    }

    func testAnOversizedPhotoIsScaledDownAndAValidOneKeepsItsBytes() throws {
        let store = try BackupTestStore()
        let valid = BackupFixtures.validManifest()
        let photo = valid.manifest.photos[0]
        var files = valid.files
        files[photo.fullFile] = TestImages.jpeg(width: 2_000, height: 1_000)

        let opened = try open(valid.manifest, files: files, in: store)
        defer { opened.close() }

        let size = try XCTUnwrap(TestImages.pixelSize(of: Data(contentsOf: opened.url(for: photo.fullFile))))
        XCTAssertEqual(max(size.width, size.height), TakeLimits.fullPhotoMaxPixels)
        XCTAssertEqual(try Data(contentsOf: opened.url(for: photo.thumbnailFile)), BackupFixtures.otherPhoto.thumbnail)
    }

    func testFlavourValuesOutOfRangeAreDamaged() throws {
        let store = try BackupTestStore()
        var valid = BackupFixtures.validManifest()
        valid.manifest.cabinet = [CabinetRecord(BackupFixtures.cabinetItem())]
        let opened = try open(valid.manifest, files: valid.files, in: store)
        opened.close() // abv is a percentage, so 25 is fine

        let changes: [(inout FlavorProfile) -> Void] = [{ $0.bitterness = 1.5 }, { $0.citrus = -0.1 }, { $0.abv = 101 }]
        for change in changes {
            var bad = valid
            change(&bad.manifest.cabinet[0].flavor)
            try assertRefused(try BackupFixtures.archive(manifest: BackupFixtures.encoded(bad.manifest), files: bad.files, in: try store.scratch()),
                              as: .damaged, in: store)
        }
    }
}
