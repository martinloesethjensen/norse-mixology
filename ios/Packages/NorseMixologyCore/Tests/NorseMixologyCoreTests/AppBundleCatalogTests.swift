import XCTest
@testable import NorseMixologyCore

/// Reads ios/NorseMixology/Resources — the files the app ships — not the
/// test-target copies, so a bad sync can never reach a release build (row 17).
final class AppBundleCatalogTests: XCTestCase {
    private func appResource(_ name: String) throws -> Data {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NorseMixologyCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NorseMixologyCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios
        return try Data(contentsOf: ios.appending(path: "NorseMixology/Resources/\(name)"))
    }

    func testShippedCatalogBootstrapsCleanly() throws {
        let paths = try CatalogFixtures.tempPaths()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let bundled = BundledCatalog(
            manifestData: try appResource("manifest.json"),
            taxonomyData: try appResource("taxonomy.json"),
            recipesData: try appResource("recipes.json")
        )
        guard case .loaded(let catalog) = CatalogBootstrap.run(paths: paths, bundled: bundled) else {
            return XCTFail("the shipped catalog does not bootstrap")
        }
        XCTAssertEqual(catalog.meta.source, .bundled)
        XCTAssertGreaterThanOrEqual(catalog.recipes.count, 150)
    }

    func testTestResourcesMatchTheShippedCatalog() throws {
        XCTAssertEqual(try CatalogFixtures.taxonomyData(), try appResource("taxonomy.json"))
        XCTAssertEqual(try CatalogFixtures.recipesData(), try appResource("recipes.json"))
    }
}
