import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Backup spec §3/§4: the states the Settings screen and restore sheet follow.
@MainActor
final class BackupViewModelTests: XCTestCase {
    private func makeViewModel(_ store: BackupTestStore, onRestored: @escaping @MainActor () -> Void = {}) throws -> BackupViewModel {
        BackupViewModel(container: store.container, appVersion: "1.0", temporaryDirectory: try store.scratch(), onRestored: onRestored)
    }

    func testMakingABackupEndsReadyWithAFile() async throws {
        let store = try BackupTestStore()
        try BackupFixtures.populate(store.container.mainContext)
        let vm = try makeViewModel(store)

        await vm.makeBackup()

        guard case .ready(let url) = vm.state else { return XCTFail("expected ready, got \(vm.state)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        vm.cancel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "dismissing removes the file")
    }

    func testAnUnsavedEditIsIncludedInTheBackup() async throws {
        let store = try BackupTestStore()
        let recipeId = UUID()
        store.container.mainContext.insert(RecipeTake(recipeId: recipeId, recipeName: "A", rating: 3, notes: "typed just now"))
        let vm = try makeViewModel(store)

        await vm.makeBackup()

        guard case .ready(let url) = vm.state else { return XCTFail("expected ready, got \(vm.state)") }
        let opened = try BackupReader.open(url, temporaryDirectory: try store.scratch())
        defer { opened.close() }
        XCTAssertEqual(opened.manifest.takes.map(\.notes), ["typed just now"])
    }

    func testOpeningAndRestoringReportsTheResultAndRefreshes() async throws {
        let source = try BackupTestStore()
        try BackupFixtures.populate(ModelContext(source.container))
        let archive = try BackupWriter.write(container: source.container, appVersion: "1.0", temporaryDirectory: try source.scratch())
        let target = try BackupTestStore()
        var refreshes = 0
        let vm = try makeViewModel(target) { refreshes += 1 }

        await vm.open(url: archive)
        guard case .opened(let summary) = vm.state else { return XCTFail("expected opened, got \(vm.state)") }
        XCTAssertEqual(summary.photos, 2)

        vm.confirmRestore()

        guard case .finished(let result) = vm.state else { return XCTFail("expected finished, got \(vm.state)") }
        XCTAssertEqual(result.photosAdded, 2)
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<CabinetItem>()), 2)

        await vm.open(url: archive)
        vm.confirmRestore()
        XCTAssertEqual(vm.state, .finished(RestoreResult()), "the same file again changes nothing")
    }

    func testABadFileFails() async throws {
        let store = try BackupTestStore()
        let junk = try store.scratch().appendingPathComponent("junk.nmbackup")
        try Data("nope".utf8).write(to: junk)
        let vm = try makeViewModel(store)

        await vm.open(url: junk)

        XCTAssertEqual(vm.state, .failed(.notABackup))
        vm.cancel()
        XCTAssertEqual(vm.state, .idle)
    }

    func testRestoreOnlyRunsFromAnOpenedBackup() async throws {
        let store = try BackupTestStore()
        let vm = try makeViewModel(store)

        vm.confirmRestore()

        XCTAssertEqual(vm.state, .idle)
    }

    func testOpeningASecondFileReplacesTheFirstAndCleansUp() async throws {
        let store = try BackupTestStore()
        let first = BackupFixtures.validManifest()
        let second = BackupFixtures.validManifest()
        let firstArchive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(first.manifest), files: first.files, in: try store.scratch())
        var secondManifest = second.manifest
        secondManifest.takes.append(TakeRecord(id: UUID(), recipeId: UUID(), recipeName: "B", rating: 1, notes: "", updatedAt: BackupFixtures.date(1)))
        let secondArchive = try BackupFixtures.archive(manifest: BackupFixtures.encoded(secondManifest), files: second.files, in: try store.scratch())
        let temporary = try store.scratch()
        let vm = BackupViewModel(container: store.container, appVersion: "1.0", temporaryDirectory: temporary)

        await vm.open(url: firstArchive)
        await vm.open(url: secondArchive)

        guard case .opened(let summary) = vm.state else { return XCTFail("expected opened, got \(vm.state)") }
        XCTAssertEqual(summary.takes, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path).count, 1, "first folder removed")
        vm.cancel()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), [])
    }
}
