import XCTest
import SwiftData
@testable import NorseMixologyCore

/// TEMPORARY: prints a version 1 backup for committing as a fixture. Removed in the next commit.
final class FixtureGeneratorTests: XCTestCase {
    func testPrintVersion1Fixture() throws {
        let store = try BackupTestStore()
        try BackupFixtures.populate(ModelContext(store.container))
        let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00Z")!
        let archive = try BackupWriter.write(container: store.container, appVersion: "1.0 (1)", now: now,
                                             temporaryDirectory: try store.scratch())
        print("NMFIXTURE-BEGIN" + (try Data(contentsOf: archive)).base64EncodedString() + "NMFIXTURE-END")
    }
}
