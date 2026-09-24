import Foundation
import NorseMixologyCore

enum CatalogConfig {
    static let baseURL = URL(string: "https://martinloeseth.dev/norse-catalog/")!
}

/// Connects the core catalog pipeline to this app: its bundle, its
/// Application Support directory, and its catalog host.
enum CatalogLaunch {
    static func bootstrap() -> CatalogBootstrapResult {
        let paths: CatalogPaths
        do {
            paths = try CatalogPaths.applicationSupport()
        } catch {
            return .unavailable(reason: "Application Support unavailable: \(error)")
        }
        return CatalogBootstrap.run(paths: paths, bundled: bundledCatalog())
    }

    static func refresh(current: CatalogMeta) async {
        guard let paths = try? CatalogPaths.applicationSupport() else { return }
        let outcome = await CatalogUpdater(baseURL: CatalogConfig.baseURL, paths: paths).refresh(current: current)
        switch outcome {
        case .failed(let error):
            AppLog.catalog.error("Catalog refresh failed: \(String(describing: error), privacy: .public)")
        default:
            AppLog.catalog.info("Catalog refresh: \(String(describing: outcome), privacy: .public)")
        }
    }

    /// Missing files become empty data, which the bootstrap treats as an
    /// unusable bundled catalog (and falls back to the stored one).
    private static func bundledCatalog() -> BundledCatalog {
        func resource(_ name: String) -> Data {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                AppLog.catalog.error("Bundled \(name, privacy: .public).json missing")
                return Data()
            }
            return data
        }
        return BundledCatalog(manifestData: resource("manifest"), taxonomyData: resource("taxonomy"), recipesData: resource("recipes"))
    }
}
