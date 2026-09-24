import Foundation

/// The catalog files shipped inside the app. Empty data means "missing from
/// the bundle" and is handled like any other unusable bundled catalog.
public struct BundledCatalog: Sendable {
    public let manifestData: Data
    public let taxonomyData: Data
    public let recipesData: Data

    public init(manifestData: Data, taxonomyData: Data, recipesData: Data) {
        self.manifestData = manifestData
        self.taxonomyData = taxonomyData
        self.recipesData = recipesData
    }
}

public enum CatalogBootstrapResult: Equatable, Sendable {
    case loaded(LoadedCatalog)
    case unavailable(reason: String)
}

/// Decides, once per launch, which catalog the app runs on. Never throws:
/// every failure falls back to the next-best catalog, and only when there is
/// none at all does it report `.unavailable`.
public enum CatalogBootstrap {
    public static func run(paths: CatalogPaths, bundled: BundledCatalog) -> CatalogBootstrapResult {
        do {
            try paths.prepareDirectory()
        } catch {
            return .unavailable(reason: "Catalog directory unavailable: \(error)")
        }
        paths.removeAllStaging()

        let usableManifest: CatalogManifest?
        do {
            usableManifest = try CatalogManifest.decode(from: bundled.manifestData)
        } catch {
            AppLog.catalog.error("Bundled catalog manifest unusable: \(String(describing: error), privacy: .public)")
            usableManifest = nil
        }

        var existing: LoadedCatalog?
        do {
            existing = try CatalogDatabase.load(from: paths.live)
        } catch CatalogError.missingDatabase {
            AppLog.catalog.info("No catalog database yet; building from the bundled catalog")
        } catch {
            AppLog.catalog.error("Catalog database unreadable, rebuilding: \(String(describing: error), privacy: .public)")
        }

        if let existing {
            guard let usableManifest, usableManifest.generatedAt > existing.meta.generatedAt else {
                return .loaded(existing)
            }
            AppLog.catalog.info("Bundled catalog is newer than the stored one; rebuilding")
        }

        guard let bundledManifest = usableManifest else {
            return .unavailable(reason: "No readable catalog database and the bundled catalog is unusable")
        }

        let staging = paths.makeStaging()
        do {
            try CatalogImporter.build(
                at: staging,
                manifest: bundledManifest,
                taxonomyData: bundled.taxonomyData,
                recipesData: bundled.recipesData,
                source: .bundled,
                etag: nil
            )
            try paths.promote(staging)
            return .loaded(try CatalogDatabase.load(from: paths.live))
        } catch {
            paths.removeStaging(staging)
            AppLog.catalog.error("Rebuilding from the bundled catalog failed: \(String(describing: error), privacy: .public)")
            if let existing {
                return .loaded(existing)
            }
            return .unavailable(reason: "Rebuilding from the bundled catalog failed: \(error)")
        }
    }
}
