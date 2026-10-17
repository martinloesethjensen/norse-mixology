import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Backup spec §3/§5: the archive format, the writer, temporary-file clean-up
/// and the device-backup check.
final class BackupWriterTests: XCTestCase {
    func testArchivePacksAndUnpacksAFolder() throws {
        let store = try BackupTestStore()
        let archive = try BackupFixtures.archive(manifest: Data("{}".utf8), files: ["photos/a.jpg": Data(repeating: 1, count: 3_000)],
                                                 in: try store.scratch())
        let target = try store.scratch()

        try BackupArchive.unpack(archive, into: target)

        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), Data("{}".utf8))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("photos/a.jpg")).count, 3_000)
    }

    func testAnythingThatIsNotAnArchiveIsRefused() throws {
        let store = try BackupTestStore()
        let folder = try store.scratch()
        let junk = folder.appendingPathComponent("junk.nmbackup")
        try Data("hello".utf8).write(to: junk)
        let empty = folder.appendingPathComponent("empty.nmbackup")
        try Data().write(to: empty)

        for file in [junk, empty, folder.appendingPathComponent("missing.nmbackup")] {
            XCTAssertThrowsError(try BackupArchive.unpack(file, into: try store.scratch())) { error in
                XCTAssertEqual(error as? BackupError, .notABackup, file.lastPathComponent)
            }
        }
    }

    func testTheWriterStoresEverythingWithPhotosAsFiles() throws {
        let store = try BackupTestStore()
        let (_, photoIds) = try BackupFixtures.populate(ModelContext(store.container))
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!

        let archive = try BackupWriter.write(container: store.container, appVersion: "1.0", now: now, temporaryDirectory: try store.scratch())

        XCTAssertEqual(archive.lastPathComponent, "Norse Mixology Backup 2026-10-17.nmbackup")
        let unpacked = try store.scratch()
        try BackupArchive.unpack(archive, into: unpacked)
        let manifest = try BackupJSON.decoder().decode(BackupManifest.self, from: Data(contentsOf: unpacked.appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.formatVersion, 1)
        XCTAssertEqual(manifest.appVersion, "1.0")
        XCTAssertEqual(manifest.createdAt, now)
        XCTAssertEqual(manifest.cabinet.count, 2)
        XCTAssertEqual(manifest.favourites.count, 1)
        XCTAssertEqual(manifest.shopping.count, 1)
        XCTAssertEqual(manifest.takes.map(\.notes), ["Orange peel."])
        XCTAssertEqual(manifest.photos.map(\.id), photoIds, "oldest first")
        let first = manifest.photos[0]
        XCTAssertEqual(try Data(contentsOf: unpacked.appendingPathComponent(first.fullFile)), Data(repeating: 7, count: 4_000))
        XCTAssertEqual(try Data(contentsOf: unpacked.appendingPathComponent(first.thumbnailFile)), Data([1, 2]))
    }

    func testAnEmptyStoreGivesAValidBackupWithNothingInIt() throws {
        let store = try BackupTestStore()

        let archive = try BackupWriter.write(container: store.container, appVersion: "1.0", temporaryDirectory: try store.scratch())

        let opened = try BackupReader.open(archive, temporaryDirectory: try store.scratch())
        defer { opened.close() }
        XCTAssertEqual(opened.summary.cabinetItems + opened.summary.favourites + opened.summary.shoppingItems
                       + opened.summary.takes + opened.summary.photos, 0)
    }

    func testOnlyTheArchiveIsLeftBehind() throws {
        let store = try BackupTestStore()
        try BackupFixtures.populate(ModelContext(store.container))
        let temporary = try store.scratch()

        let archive = try BackupWriter.write(container: store.container, appVersion: "1.0", temporaryDirectory: temporary)

        let workspace = archive.deletingLastPathComponent()
        XCTAssertTrue(workspace.lastPathComponent.hasPrefix(BackupWriter.temporaryPrefix))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.path), [archive.lastPathComponent])
    }

    func testStaleTemporaryFilesAreCleanedUp() throws {
        let store = try BackupTestStore()
        let temporary = try store.scratch()
        let stale = temporary.appendingPathComponent(BackupWriter.temporaryPrefix + "old", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        let unrelated = temporary.appendingPathComponent("keep-me.txt")
        try Data("x".utf8).write(to: unrelated)

        BackupWriter.cleanUpStaleFiles(in: temporary)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testTheStoreIsPutBackIntoDeviceBackups() throws {
        let store = try BackupTestStore()
        var file = try store.scratch().appendingPathComponent("store.sqlite")
        try Data("db".utf8).write(to: file)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try file.setResourceValues(excluded)

        XCTAssertTrue(StoreBackupCheck.ensureIncluded(file))
        file.removeAllCachedResourceValues()
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
        XCTAssertFalse(StoreBackupCheck.ensureIncluded(file), "nothing to fix the second time")
    }
}
