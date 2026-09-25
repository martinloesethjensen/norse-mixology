import Foundation
import NorseMixologyCore

enum CatalogConfig {
    static let baseURL = URL(string: "https://martinloeseth.dev/norse-catalog/")!
}

/// Connects the core catalog pipeline to this app: its bundle, its
/// Application Support directory, and its catalog host.
enum CatalogLaunch {
    /// The one bootstrap of this process. `.task` runs once per scene (iPad
    /// multi-window), so without this two bootstraps — and two refreshes —
    /// could race on the same catalog directory.
    @MainActor private static var shared: Task<CatalogBootstrapResult, Never>?

    /// Bootstraps the catalog at most once per process; every caller awaits the
    /// same result. The background refresh starts exactly once, and only after
    /// a catalog was loaded.
    @MainActor
    static func load() async -> CatalogBootstrapResult {
        if let shared {
            return await shared.value
        }
        let task = Task.detached(priority: .userInitiated) { () -> CatalogBootstrapResult in
            let result = bootstrap()
            if case .loaded(let catalog) = result {
                let meta = catalog.meta
                Task.detached(priority: .background) { await refresh(current: meta) }
            }
            return result
        }
        shared = task
        return await task.value
    }

    private static func bootstrap() -> CatalogBootstrapResult {
        let paths: CatalogPaths
        do {
            paths = try CatalogPaths.applicationSupport()
        } catch {
            return .unavailable(reason: "Application Support unavailable: \(error)")
        }
        return CatalogBootstrap.run(paths: paths, bundled: bundledCatalog())
    }

    private static func refresh(current: CatalogMeta) async {
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
