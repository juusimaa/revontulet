import AuroraCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import AlertServer

@Suite("Registration routes")
struct RegistrationRoutesTests {
    private let now = utc("2026-11-03T20:15:00Z")
    private let token = testToken(1)

    private func withApp(rateLimiter: RateLimiter = RateLimiter(),
                         _ test: @escaping @Sendable (any TestClientProtocol, RegistrationStore) async throws -> Void) async throws {
        try await withTemporaryStore { store, _ in
            let dependencies = try AppDependencies(
                store: store, health: HealthStatus(), rateLimiter: rateLimiter, zones: AlertZones.all(),
                pushSender: FakePushSender(), apnsTopic: "fi.juusimaa.revontulet", now: { [now] in now })
            try await buildApplication(dependencies: dependencies, port: 0).test(.router) { client in
                try await test(client, store)
            }
        }
    }

    private func put(_ client: any TestClientProtocol, _ json: String, forwardedFor: String = "203.0.113.7") async throws -> TestResponse {
        try await client.execute(
            uri: "/v1/registration", method: .put,
            headers: [.contentType: "application/json", HTTPField.Name("X-Forwarded-For")!: forwardedFor],
            body: ByteBuffer(string: json))
    }

    @Test func putStoresRegistration() async throws {
        try await withApp { client, store in
            let response = try await put(client, #"{"token":"\#(token)","zone":"OUJ","threshold":"moderate"}"#)

            #expect(response.status == .noContent)
            let stored = try await store.registration(token: token)
            #expect(stored == Registration(token: token, zone: "OUJ", threshold: .moderate,
                                           confirmedAt: utc("2026-11-03T00:00:00Z")))
        }
    }

    @Test func putUpdatesExistingRegistration() async throws {
        try await withApp { client, store in
            _ = try await put(client, #"{"token":"\#(token)","zone":"OUJ","threshold":"moderate"}"#)
            let response = try await put(client, #"{"token":"\#(token)","zone":"KEV","threshold":"high"}"#)

            #expect(response.status == .noContent)
            #expect(try await store.registration(token: token)?.zone == "KEV")
            #expect(try await store.registrations(inZone: "OUJ").isEmpty)
        }
    }

    @Test(arguments: [
        (#"{"token":"ABC","zone":"OUJ","threshold":"high"}"#, AlertAPIError.invalidToken),
        (#"{"token":"\#(testToken(1))","zone":"XXX","threshold":"high"}"#, .invalidZone),
        (#"{"token":"\#(testToken(1))","zone":"OUJ","threshold":"low"}"#, .invalidThreshold),
        (#"{"token":"\#(testToken(1))","zone":"OUJ"}"#, .invalidBody),
        ("not json", .invalidBody),
        ("", .invalidBody),
    ])
    func invalidBodyIsRejected(body: String, error: AlertAPIError) async throws {
        try await withApp { client, store in
            let response = try await put(client, body)

            #expect(response.status == .badRequest)
            #expect(String(buffer: response.body) == #"{"error":"\#(error.rawValue)"}"#)
            #expect(try await store.registration(token: testToken(1)) == nil)
        }
    }

    @Test func rateLimitedAfterThirtyRequests() async throws {
        try await withApp(rateLimiter: RateLimiter(limit: 30, window: 600)) { client, _ in
            for _ in 0..<30 {
                let response = try await put(client, #"{"token":"\#(token)","zone":"OUJ","threshold":"high"}"#)
                #expect(response.status == .noContent)
            }
            let limited = try await put(client, #"{"token":"\#(token)","zone":"OUJ","threshold":"high"}"#)
            #expect(limited.status == .tooManyRequests)
            #expect(limited.headers[.retryAfter] == "600")

            let otherClient = try await put(client, #"{"token":"\#(token)","zone":"OUJ","threshold":"high"}"#,
                                            forwardedFor: "198.51.100.1")
            #expect(otherClient.status == .noContent)
        }
    }

    @Test func healthIsNotRateLimited() async throws {
        try await withApp(rateLimiter: RateLimiter(limit: 1, window: 600)) { client, _ in
            for _ in 0..<3 {
                let response = try await client.execute(uri: "/v1/health", method: .get)
                #expect(response.status == .serviceUnavailable)
            }
        }
    }
}
