import AuroraCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import AlertServer

@Suite("Application")
struct ApplicationTests {
    private let now = Date(timeIntervalSince1970: 1_761_400_000)

    private func withApp(health: HealthStatus, _ test: @escaping @Sendable (any TestClientProtocol) async throws -> Void) async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("alerts-\(UUID().uuidString).db").path
        let store = try await RegistrationStore.open(path: path)
        let app = try buildApplication(
            dependencies: AppDependencies(store: store, health: health, rateLimiter: RateLimiter(), zones: AlertZones.all()),
            port: 0
        )
        do {
            try await app.test(.router, test)
        } catch {
            try? await store.close()
            try? FileManager.default.removeItem(atPath: path)
            throw error
        }
        try await store.close()
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test func healthIsUnavailableBeforeAnyCycle() async throws {
        try await withApp(health: HealthStatus(now: { [now] in now })) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }

    @Test func healthIsOkWithinFifteenMinutesOfASuccessfulCycle() async throws {
        let clock = TestClock(now)
        let health = HealthStatus(now: { clock.now })
        await health.recordSuccess()

        try await withApp(health: health) { client in
            clock.now = now.addingTimeInterval(15 * 60)
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json; charset=utf-8")
                #expect(String(buffer: response.body) == #"{"status":"ok"}"#)
            }
            clock.now = now.addingTimeInterval(15 * 60 + 1)
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }

    @Test func apiErrorResponseFormat() async throws {
        let router = Router()
        router.get("error") { _, _ in Response.apiError(.invalidZone) }

        try await Application(router: router).test(.router) { client in
            try await client.execute(uri: "/error", method: .get) { response in
                #expect(response.status == .badRequest)
                #expect(response.headers[.contentType] == "application/json; charset=utf-8")
                #expect(String(buffer: response.body) == #"{"error":"invalidZone"}"#)
            }
        }
    }

    @Test func loggerNeverLogsBelowInfo() {
        #expect(makeLogger(level: "trace").logLevel == .info)
        #expect(makeLogger(level: "debug").logLevel == .info)
        #expect(makeLogger(level: "warning").logLevel == .warning)
        #expect(makeLogger(level: nil).logLevel == .info)
    }
}

/// A mutable clock shared between a test and the code under test.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ now: Date) { value = now }

    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
