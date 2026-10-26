import Foundation
import HTTPTypes
import Hummingbird

/// Sliding-window request limit per key (FR-017). In memory only: never persisted or logged.
public actor RateLimiter {
    public enum Decision: Sendable, Equatable {
        case allowed
        /// Seconds until the next request would be allowed.
        case limited(retryAfter: Int)
    }

    private let limit: Int
    private let window: TimeInterval
    /// Times of allowed requests within the window, oldest first.
    private var requests: [String: [Date]] = [:]
    private var lastSweep: Date?

    /// Defaults to 30 requests per 10 minutes, the per-address limit of contracts/alert-api.md.
    public init(limit: Int = 30, window: TimeInterval = 600) {
        self.limit = limit
        self.window = window
    }

    /// Counts a request for `key` at `now` if it is within the limit.
    public func check(_ key: String, now: Date) -> Decision {
        sweepIfDue(now: now)
        var times = requests[key, default: []]
        times.removeAll { now.timeIntervalSince($0) >= window }
        guard times.count < limit else {
            requests[key] = times
            let retryAfter = times[0].addingTimeInterval(window).timeIntervalSince(now)
            return .limited(retryAfter: max(1, Int(retryAfter.rounded(.up))))
        }
        times.append(now)
        requests[key] = times
        return .allowed
    }

    /// Number of keys currently remembered.
    var trackedClients: Int { requests.count }

    /// Forgets keys with no request within the window, at most once per window, so addresses
    /// are not kept longer than needed.
    private func sweepIfDue(now: Date) {
        if let lastSweep, now.timeIntervalSince(lastSweep) < window { return }
        lastSweep = now
        requests = requests.filter { now.timeIntervalSince($0.value.last ?? .distantPast) < window }
    }
}

/// Applies a `RateLimiter` per client address, taken from the proxy's `X-Forwarded-For`.
public struct RateLimitMiddleware<Context: RequestContext>: RouterMiddleware {
    let limiter: RateLimiter
    let now: @Sendable () -> Date

    public init(limiter: RateLimiter, now: @escaping @Sendable () -> Date = Date.init) {
        self.limiter = limiter
        self.now = now
    }

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let address = Self.clientAddress(forwardedFor: request.headers[Self.forwardedFor])
        switch await limiter.check(address, now: now()) {
        case .allowed:
            return try await next(request, context)
        case .limited(let retryAfter):
            return Response(status: .tooManyRequests, headers: [.retryAfter: String(retryAfter)])
        }
    }

    static var forwardedFor: HTTPField.Name { HTTPField.Name("X-Forwarded-For")! }

    /// The first `X-Forwarded-For` entry; the proxy is the only client, so requests without the
    /// header share one bucket.
    static func clientAddress(forwardedFor: String?) -> String {
        guard let forwardedFor else { return "" }
        return forwardedFor.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
