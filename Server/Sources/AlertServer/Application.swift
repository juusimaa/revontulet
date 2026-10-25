import AuroraCore
import Foundation
import Hummingbird
import Logging

/// What the HTTP routes need.
public struct AppDependencies: Sendable {
    public var store: RegistrationStore
    public var health: HealthStatus
    public var rateLimiter: RateLimiter
    public var zones: [AlertZone]

    public init(store: RegistrationStore, health: HealthStatus, rateLimiter: RateLimiter, zones: [AlertZone]) {
        self.store = store
        self.health = health
        self.rateLimiter = rateLimiter
        self.zones = zones
    }
}

/// Whether the evaluation loop has succeeded recently, for `GET /v1/health`.
public actor HealthStatus {
    /// The service is healthy while the last successful cycle is at most this old.
    static let maxAge: TimeInterval = 15 * 60

    private let now: @Sendable () -> Date
    private var lastSuccess: Date?

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func recordSuccess() {
        lastSuccess = now()
    }

    public var isHealthy: Bool {
        guard let lastSuccess else { return false }
        return now().timeIntervalSince(lastSuccess) <= Self.maxAge
    }
}

/// The router for `/v1`. No request-logging middleware, ever (FR-013, contracts/alert-api.md).
func buildRouter(dependencies: AppDependencies) -> Router<BasicRequestContext> {
    let router = Router()
    let v1 = router.group("v1")

    v1.get("health") { _, _ -> Response in
        guard await dependencies.health.isHealthy else { return Response(status: .serviceUnavailable) }
        return .json(#"{"status":"ok"}"#)
    }

    // Registration routes (US1–US3) go in this group so they share the per-address limit.
    _ = v1.group("registration")
        .add(middleware: RateLimitMiddleware(limiter: dependencies.rateLimiter))

    return router
}

/// The HTTP application, listening on all interfaces inside the container network.
public func buildApplication(dependencies: AppDependencies, port: Int, logger: Logger = makeLogger()) -> some ApplicationProtocol {
    Application(
        router: buildRouter(dependencies: dependencies),
        configuration: .init(address: .hostname("0.0.0.0", port: port), serverName: "revontulet-alerts"),
        logger: logger
    )
}

/// The service logger. Never below `info`: Hummingbird logs request details at `debug`, and
/// nothing may log bodies, tokens or client addresses (FR-013).
public func makeLogger(level: String? = ProcessInfo.processInfo.environment["LOG_LEVEL"]) -> Logger {
    var logger = Logger(label: "revontulet-alerts")
    let requested = level.flatMap(Logger.Level.init(rawValue:)) ?? .info
    logger.logLevel = max(requested, .info)
    return logger
}

extension Response {
    /// A JSON response; `json` must already be encoded.
    static func json(_ json: String, status: HTTPResponse.Status = .ok) -> Response {
        Response(
            status: status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: ResponseBody(byteBuffer: ByteBuffer(string: json))
        )
    }

    /// `400 {"error": …}` per contracts/alert-api.md.
    static func apiError(_ error: AlertAPIError) -> Response {
        .json(#"{"error":"\#(error.rawValue)"}"#, status: .badRequest)
    }
}
