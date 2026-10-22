import Foundation
import Synchronization
@testable import AuroraCore

/// Serves fixture files by FMI stored query id, and records every requested URL.
final class StubHTTPClient: HTTPClient {
    enum Response: Sendable {
        case fixture(String, status: Int = 200)
        case failure
    }

    struct StubError: Error {}

    private let responses: [String: Response]
    private let requested = Mutex<[URL]>([])

    /// - Parameter responses: stored query id (e.g. `fmi::observations::magnetometer::simple`) → response.
    init(_ responses: [String: Response]) {
        self.responses = responses
    }

    var requestedURLs: [URL] {
        requested.withLock { $0 }
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        requested.withLock { $0.append(url) }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "storedquery_id" }?.value ?? ""
        switch responses[query] {
        case .fixture(let name, let status):
            return (try Fixtures.data(name), status)
        case .failure, nil:
            throw StubError()
        }
    }
}
