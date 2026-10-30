import Foundation
import Synchronization
@testable import AuroraCore

/// Serves fixture files by FMI stored query id (or, for URLs without one such as NOAA's, by the
/// file name, e.g. `alerts.json`), and records every requested URL.
final class StubHTTPClient: HTTPClient {
    enum Response: Sendable {
        case fixture(String, status: Int = 200)
        case data(Data, status: Int = 200)
        case failure
    }

    struct StubError: Error {}

    private let responses: Mutex<[String: Response]>
    private let requested = Mutex<[URL]>([])

    /// - Parameter responses: stored query id (e.g. `fmi::observations::magnetometer::simple`) or
    ///   file name (e.g. `alerts.json`) → response.
    init(_ responses: [String: Response]) {
        self.responses = Mutex(responses)
    }

    /// Changes the response for a stored query, e.g. to simulate going offline.
    func set(_ query: String, _ response: Response) {
        responses.withLock { $0[query] = response }
    }

    var requestedURLs: [URL] {
        requested.withLock { $0 }
    }

    /// How many requests went to URLs containing `fragment`.
    func count(_ fragment: String) -> Int {
        requestedURLs.filter { $0.absoluteString.contains(fragment) }.count
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        requested.withLock { $0.append(url) }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "storedquery_id" }?.value ?? url.lastPathComponent
        switch responses.withLock({ $0[query] }) {
        case .fixture(let name, let status):
            return (try Fixtures.data(name), status)
        case .data(let data, let status):
            return (data, status)
        case .failure, nil:
            throw StubError()
        }
    }
}
