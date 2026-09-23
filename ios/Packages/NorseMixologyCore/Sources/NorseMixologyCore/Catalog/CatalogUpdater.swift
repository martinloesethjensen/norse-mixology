import Foundation

public enum CatalogUpdateOutcome: Equatable, Sendable {
    case notModified
    case upToDate
    case updated(contentVersion: String)
    case failed(CatalogError)
}

/// Checks the catalog host for a newer manifest and, if there is one, builds
/// it into the staging database and swaps it in for the next launch. Never
/// throws: whatever goes wrong, the live catalog is left exactly as it was.
public struct CatalogUpdater: Sendable {
    public static let manifestByteLimit = 65_536

    private let v1URL: URL
    private let session: URLSession
    private let paths: CatalogPaths
    private let promote: @Sendable (CatalogPaths) throws -> Void

    public init(
        baseURL: URL,
        session: URLSession = CatalogUpdater.makeSession(),
        paths: CatalogPaths,
        promote: @escaping @Sendable (CatalogPaths) throws -> Void = { try $0.promoteStaging() }
    ) {
        self.v1URL = baseURL.appending(path: "v1", directoryHint: .isDirectory)
        self.session = session
        self.paths = paths
        self.promote = promote
    }

    /// Ephemeral with no URL cache: conditional requests are driven by the
    /// ETag stored in `catalog_meta`, not by an HTTP cache that could hand
    /// back a stale body.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func refresh(current: CatalogMeta) async -> CatalogUpdateOutcome {
        do {
            return try await performRefresh(current: current)
        } catch {
            paths.removeStaging()
            if let catalogError = error as? CatalogError {
                return .failed(catalogError)
            }
            return .failed(.transport(String(describing: error)))
        }
    }

    private func performRefresh(current: CatalogMeta) async throws -> CatalogUpdateOutcome {
        var request = URLRequest(url: v1URL.appending(path: "manifest.json"))
        if let etag = current.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (response, manifestData) = try await fetch(request, limit: Self.manifestByteLimit)
        if response.statusCode == 304 {
            return .notModified
        }
        guard response.statusCode == 200 else {
            throw CatalogError.http(status: response.statusCode)
        }
        let manifest = try CatalogManifest.decode(from: manifestData)
        // A CDN edge can still serve an older manifest after we applied a newer one.
        guard manifest.contentVersion != current.contentVersion, manifest.generatedAt > current.generatedAt else {
            return .upToDate
        }

        let taxonomyData = try await fetchFile(manifest.taxonomy)
        let recipesData = try await fetchFile(manifest.recipes)
        try CatalogImporter.build(
            at: paths.staging,
            manifest: manifest,
            taxonomyData: taxonomyData,
            recipesData: recipesData,
            source: .remote,
            etag: response.value(forHTTPHeaderField: "ETag")
        )
        do {
            try promote(paths)
        } catch {
            throw CatalogError.fileSystem(String(describing: error))
        }
        return .updated(contentVersion: manifest.contentVersion)
    }

    private func fetchFile(_ entry: CatalogManifest.FileEntry) async throws -> Data {
        let (response, data) = try await fetch(URLRequest(url: v1URL.appending(path: entry.path)), limit: CatalogManifest.maxFileBytes)
        guard response.statusCode == 200 else {
            throw CatalogError.http(status: response.statusCode)
        }
        return data
    }

    /// Streams the body and stops as soon as it exceeds `limit`, so an
    /// oversized response is never held in memory whole.
    private func fetch(_ request: URLRequest, limit: Int) async throws -> (HTTPURLResponse, Data) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.transport("Not an HTTP response")
        }
        let name = request.url?.lastPathComponent ?? "response"
        if http.expectedContentLength > Int64(limit) {
            throw CatalogError.fileTooLarge(name, Int(http.expectedContentLength))
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                throw CatalogError.fileTooLarge(name, data.count)
            }
        }
        return (http, data)
    }
}
