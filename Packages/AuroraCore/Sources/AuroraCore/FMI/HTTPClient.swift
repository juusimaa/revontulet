import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP access the core needs; platforms and tests can provide their own.
public protocol HTTPClient: Sendable {
    /// Performs a GET request and returns the body and HTTP status code.
    func get(_ url: URL) async throws -> (Data, Int)
}

/// `HTTPClient` backed by URLSession. Responses are gzip-decoded automatically.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.httpAdditionalHeaders = ["Accept-Encoding": "gzip"]
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        let (data, response) = try await session.data(from: url)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
