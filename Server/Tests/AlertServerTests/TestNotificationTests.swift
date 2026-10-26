import AuroraCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import AlertServer

@Suite("Test notification")
struct TestNotificationTests {
    private let now = utc("2026-11-03T20:15:00Z")
    private let token = testToken(1)

    private func withApp(
        sender: FakePushSender = FakePushSender(),
        _ test: @escaping @Sendable (any TestClientProtocol, RegistrationStore) async throws -> Void
    ) async throws {
        try await withTemporaryStore { store, _ in
            let dependencies = try AppDependencies(
                store: store, health: HealthStatus(), rateLimiter: RateLimiter(), zones: AlertZones.all(),
                pushSender: sender, apnsTopic: "fi.juusimaa.revontulet", now: { [now] in now })
            try await buildApplication(dependencies: dependencies, port: 0).test(.router) { client in
                try await test(client, store)
            }
        }
    }

    private func sendTest(_ client: any TestClientProtocol, _ json: String) async throws -> TestResponse {
        try await client.execute(
            uri: "/v1/registration/test", method: .post,
            headers: [.contentType: "application/json", HTTPField.Name("X-Forwarded-For")!: "203.0.113.7"],
            body: ByteBuffer(string: json))
    }

    @Test func sendsOneTestPush() async throws {
        let sender = FakePushSender()
        try await withApp(sender: sender) { client, store in
            try await store.upsert(RegistrationUpsert(token: token, zone: "OUJ", threshold: .high), now: now)

            let response = try await sendTest(client, #"{"token":"\#(token)"}"#)

            #expect(response.status == .accepted)
            #expect(sender.sent.count == 1)
            #expect(sender.sent.first?.token == token)
            #expect(sender.sent.first?.message.titleKey == "alert.title.test")
            #expect(sender.sent.first?.message.bodyKey == "alert.body.test")
            #expect(sender.sent.first?.message == .test)
        }
    }

    @Test func notRegisteredIsNotFound() async throws {
        let sender = FakePushSender()
        try await withApp(sender: sender) { client, _ in
            let response = try await sendTest(client, #"{"token":"\#(token)"}"#)

            #expect(response.status == .notFound)
            #expect(sender.sent.isEmpty)
        }
    }

    @Test func fourthWithinAnHourIsLimited() async throws {
        let sender = FakePushSender()
        try await withApp(sender: sender) { client, store in
            try await store.upsert(RegistrationUpsert(token: token, zone: "OUJ", threshold: .high), now: now)
            try await store.upsert(RegistrationUpsert(token: testToken(2), zone: "OUJ", threshold: .high), now: now)

            for _ in 1...3 {
                #expect(try await sendTest(client, #"{"token":"\#(token)"}"#).status == .accepted)
            }
            let fourth = try await sendTest(client, #"{"token":"\#(token)"}"#)
            let other = try await sendTest(client, #"{"token":"\#(testToken(2))"}"#)

            #expect(fourth.status == .tooManyRequests)
            #expect(fourth.headers[.retryAfter] == "3600")
            #expect(other.status == .accepted)
            #expect(sender.sent.count == 4)
        }
    }

    @Test func invalidTokenIsRejected() async throws {
        try await withApp { client, _ in
            let response = try await sendTest(client, #"{"token":"ABC"}"#)

            #expect(response.status == .badRequest)
            #expect(String(buffer: response.body) == #"{"error":"invalidToken"}"#)
        }
    }

    @Test func failedPushIsUnavailable() async throws {
        let sender = FakePushSender()
        sender.respondToAll(with: .retryable)
        try await withApp(sender: sender) { client, store in
            try await store.upsert(RegistrationUpsert(token: token, zone: "OUJ", threshold: .high), now: now)

            let response = try await sendTest(client, #"{"token":"\#(token)"}"#)

            #expect(response.status == .serviceUnavailable)
        }
    }
}
