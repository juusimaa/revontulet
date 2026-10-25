import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `AlertAPI` over URLSession (contracts/alert-api.md). Tokens are sent only in request bodies,
/// never in URLs.
public struct URLSessionAlertAPI: AlertAPI {
    /// When the service sends no `Retry-After`.
    static let defaultRetryAfter: TimeInterval = 60

    private let baseURL: URL
    private let session: URLSession

    /// - Parameter baseURL: e.g. `https://alerts.revontuletapp.com/v1`.
    public init(baseURL: URL, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func upsert(_ registration: RegistrationUpsert) async throws(AlertAPIFailure) {
        try await send("PUT", "registration", registration)
    }

    public func delete(_ token: RegistrationToken) async throws(AlertAPIFailure) {
        try await send("POST", "registration/delete", token)
    }

    public func sendTest(_ token: RegistrationToken) async throws(AlertAPIFailure) {
        try await send("POST", "registration/test", token)
    }

    private func send(_ method: String, _ path: String, _ body: some Encodable) async throws(AlertAPIFailure) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response: (Data, URLResponse)
        do {
            request.httpBody = try JSONEncoder().encode(body)
            response = try await session.data(for: request)
        } catch {
            throw .unreachable
        }
        guard let http = response.1 as? HTTPURLResponse else { throw .unreachable }
        if let failure = Self.failure(status: http.statusCode, body: response.0,
                                      retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
            throw failure
        }
    }

    /// Maps a response to a failure; nil for 2xx.
    static func failure(status: Int, body: Data, retryAfter: String?) -> AlertAPIFailure? {
        switch status {
        case 200..<300:
            return nil
        case 400:
            struct ErrorBody: Decodable { var error: AlertAPIError }
            return .rejected((try? JSONDecoder().decode(ErrorBody.self, from: body))?.error ?? .invalidBody)
        case 404:
            return .notRegistered
        case 429:
            return .rateLimited(retryAfter: retryAfter.flatMap(TimeInterval.init) ?? defaultRetryAfter)
        default:
            return .unreachable
        }
    }
}
