import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import AlertServer

@Suite("Rate limiter")
struct RateLimiterTests {
    private let start = Date(timeIntervalSince1970: 1_761_400_000)

    @Test func allowsThirtyRequestsPerTenMinutes() async {
        let limiter = RateLimiter()

        for i in 0..<30 {
            #expect(await limiter.check("203.0.113.7", now: start.addingTimeInterval(Double(i))) == .allowed)
        }
        #expect(await limiter.check("203.0.113.7", now: start.addingTimeInterval(30)) == .limited(retryAfter: 570))
    }

    @Test func clientsAreCountedSeparately() async {
        let limiter = RateLimiter(limit: 1, window: 600)

        #expect(await limiter.check("203.0.113.7", now: start) == .allowed)
        #expect(await limiter.check("198.51.100.1", now: start) == .allowed)
        #expect(await limiter.check("203.0.113.7", now: start) != .allowed)
    }

    @Test func windowSlides() async {
        let limiter = RateLimiter(limit: 2, window: 600)

        #expect(await limiter.check("a", now: start) == .allowed)
        #expect(await limiter.check("a", now: start.addingTimeInterval(300)) == .allowed)
        #expect(await limiter.check("a", now: start.addingTimeInterval(599)) == .limited(retryAfter: 1))
        #expect(await limiter.check("a", now: start.addingTimeInterval(600)) == .allowed)
        #expect(await limiter.check("a", now: start.addingTimeInterval(601)) == .limited(retryAfter: 299))
    }

    @Test func retryAfterIsRoundedUpToWholeSeconds() async {
        let limiter = RateLimiter(limit: 1, window: 600)

        #expect(await limiter.check("a", now: start) == .allowed)
        #expect(await limiter.check("a", now: start.addingTimeInterval(0.5)) == .limited(retryAfter: 600))
    }

    @Test func limitedRequestsDoNotExtendTheWindow() async {
        let limiter = RateLimiter(limit: 1, window: 600)

        #expect(await limiter.check("a", now: start) == .allowed)
        for i in 1...10 {
            _ = await limiter.check("a", now: start.addingTimeInterval(Double(i * 50)))
        }
        #expect(await limiter.check("a", now: start.addingTimeInterval(600)) == .allowed)
    }

    @Test func idleClientsAreForgotten() async {
        let limiter = RateLimiter(limit: 30, window: 600)

        _ = await limiter.check("a", now: start)
        _ = await limiter.check("b", now: start.addingTimeInterval(601))

        #expect(await limiter.trackedClients == 1)
    }

    @Test func clientAddressIsFirstForwardedEntry() {
        #expect(RateLimitMiddleware<BasicRequestContext>.clientAddress(forwardedFor: "203.0.113.7, 10.0.0.2") == "203.0.113.7")
        #expect(RateLimitMiddleware<BasicRequestContext>.clientAddress(forwardedFor: " 198.51.100.1 ") == "198.51.100.1")
        #expect(RateLimitMiddleware<BasicRequestContext>.clientAddress(forwardedFor: nil) == "")
    }

    @Test func middlewareAnswers429WithRetryAfter() async throws {
        let router = Router()
        router.add(middleware: RateLimitMiddleware(limiter: RateLimiter(limit: 2, window: 600), now: { [start] in start }))
        router.get("ping") { _, _ in HTTPResponse.Status.noContent }
        let app = Application(router: router)

        try await app.test(.router) { client in
            let headers: HTTPFields = [HTTPField.Name("X-Forwarded-For")!: "203.0.113.7, 10.0.0.2"]
            for _ in 0..<2 {
                try await client.execute(uri: "/ping", method: .get, headers: headers) { response in
                    #expect(response.status == .noContent)
                }
            }
            try await client.execute(uri: "/ping", method: .get, headers: headers) { response in
                #expect(response.status == .tooManyRequests)
                #expect(response.headers[.retryAfter] == "600")
            }
            let other: HTTPFields = [HTTPField.Name("X-Forwarded-For")!: "198.51.100.1"]
            try await client.execute(uri: "/ping", method: .get, headers: other) { response in
                #expect(response.status == .noContent)
            }
        }
    }
}
