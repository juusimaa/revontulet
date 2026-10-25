import AsyncHTTPClient
import Foundation
import Logging

/// FMI requests for `ZoneEvaluator` over AsyncHTTPClient, so the service does not depend on
/// FoundationNetworking on Linux (research R3).
public struct AsyncHTTPClientFMI: FMIHTTPClient {
    /// FMI's all-of-Finland responses are a few MB.
    static let maxResponseSize = 64 * 1024 * 1024

    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        var request = HTTPClientRequest(url: url.absoluteString)
        request.headers.add(name: "Accept-Encoding", value: "gzip")
        request.headers.add(name: "User-Agent", value: "revontulet-alerts/\(AlertServer.version)")
        let response = try await client.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: Self.maxResponseSize)
        return (Data(body.readableBytesView), Int(response.status.code))
    }

    /// A client for FMI: decompresses gzip responses.
    public static func makeClient() -> HTTPClient {
        var configuration = HTTPClient.Configuration()
        configuration.decompression = .enabled(limit: .ratio(50))
        return HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
    }
}

/// Pings the Healthchecks.io check URL, or `<url>/fail` (research R9). The ping carries no data.
public struct HealthcheckPinger: Heartbeat {
    private let url: URL?
    private let client: HTTPClient
    private let logger: Logger

    /// - Parameter url: nil disables the heartbeat (local development).
    public init(url: URL?, client: HTTPClient, logger: Logger) {
        self.url = url
        self.client = client
        self.logger = logger
    }

    public func ping(success: Bool) async {
        guard let url else { return }
        let target = success ? url : url.appendingPathComponent("fail")
        do {
            let response = try await client.execute(HTTPClientRequest(url: target.absoluteString), timeout: .seconds(10))
            if response.status.code != 200 {
                logger.warning("Heartbeat ping answered \(response.status.code)")
            }
        } catch {
            logger.warning("Heartbeat ping failed")
        }
    }
}
