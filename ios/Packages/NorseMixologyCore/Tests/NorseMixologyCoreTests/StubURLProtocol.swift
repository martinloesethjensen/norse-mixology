import Foundation

/// Serves canned responses to a URLSession built with `StubURLProtocol.session()`.
/// Tests run serially within a class, so plain static state is fine here.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var error: Error?
    }

    static var handler: ((URLRequest) -> Response)?
    static var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        requests = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let response = Self.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
