import AuroraCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import AlertServer

@Suite("Delete and retention")
struct DeleteAndRetentionTests {
    private let now = utc("2026-11-03T20:15:00Z")
    private let token = testToken(1)

    private func withApp(_ test: @escaping @Sendable (any TestClientProtocol, RegistrationStore) async throws -> Void) async throws {
        try await withTemporaryStore { store, _ in
            let dependencies = try AppDependencies(
                store: store, health: HealthStatus(), rateLimiter: RateLimiter(), zones: AlertZones.all(),
                pushSender: FakePushSender(), apnsTopic: "fi.juusimaa.revontulet", now: { [now] in now })
            try await buildApplication(dependencies: dependencies, port: 0).test(.router) { client in
                try await test(client, store)
            }
        }
    }

    private func delete(_ client: any TestClientProtocol, _ json: String) async throws -> TestResponse {
        try await client.execute(
            uri: "/v1/registration/delete", method: .post,
            headers: [.contentType: "application/json", HTTPField.Name("X-Forwarded-For")!: "203.0.113.7"],
            body: ByteBuffer(string: json))
    }

    // MARK: POST /v1/registration/delete

    @Test func deleteRemovesRegistration() async throws {
        try await withApp { client, store in
            try await store.upsert(RegistrationUpsert(token: token, zone: "OUJ", threshold: .high), now: now)
            try await store.upsert(RegistrationUpsert(token: testToken(2), zone: "OUJ", threshold: .high), now: now)

            let response = try await delete(client, #"{"token":"\#(token)"}"#)

            #expect(response.status == .noContent)
            #expect(try await store.registration(token: token) == nil)
            #expect(try await store.registration(token: testToken(2)) != nil)
        }
    }

    @Test func deleteWithoutRegistrationIsNoContent() async throws {
        try await withApp { client, _ in
            let first = try await delete(client, #"{"token":"\#(token)"}"#)
            let again = try await delete(client, #"{"token":"\#(token)"}"#)

            #expect(first.status == .noContent)
            #expect(again.status == .noContent)
        }
    }

    @Test(arguments: [
        (#"{"token":"ABC"}"#, AlertAPIError.invalidToken),
        (#"{"zone":"OUJ"}"#, .invalidBody),
        ("not json", .invalidBody),
    ])
    func invalidDeleteIsRejected(body: String, error: AlertAPIError) async throws {
        try await withApp { client, _ in
            let response = try await delete(client, body)

            #expect(response.status == .badRequest)
            #expect(String(buffer: response.body) == #"{"error":"\#(error.rawValue)"}"#)
        }
    }

    // MARK: Retention sweep

    @Test func sweepDeletesRegistrationsUnconfirmedFor180Days() async throws {
        try await withTemporaryStore { store, path in
            let day: TimeInterval = 86_400
            let old = RegistrationUpsert(token: testToken(1), zone: "OUJ", threshold: .high)
            let limit = RegistrationUpsert(token: testToken(2), zone: "OUJ", threshold: .high)
            let recent = RegistrationUpsert(token: testToken(3), zone: "KEV", threshold: .moderate)
            try await store.upsert(old, now: now.addingTimeInterval(-181 * day))
            try await store.upsert(limit, now: now.addingTimeInterval(-180 * day))
            try await store.upsert(recent, now: now.addingTimeInterval(-3 * day))

            let maintenance = Maintenance(store: store, backupPath: path + ".backup")
            let deleted = try await maintenance.sweep(now: now)

            #expect(deleted == 1)
            #expect(try await store.registration(token: old.token) == nil)
            #expect(try await store.registration(token: limit.token) != nil)
            #expect(try await store.registration(token: recent.token) != nil)
        }
    }

    // MARK: Backup

    @Test func backupOverwritesPreviousCopy() async throws {
        try await withTemporaryStore { store, path in
            let backupPath = path + ".backup"
            defer { try? FileManager.default.removeItem(atPath: backupPath) }
            let maintenance = Maintenance(store: store, backupPath: backupPath)

            try await store.upsert(RegistrationUpsert(token: testToken(1), zone: "OUJ", threshold: .high), now: now)
            try await maintenance.backup()
            try await store.delete(token: testToken(1))
            try await store.upsert(RegistrationUpsert(token: testToken(2), zone: "KEV", threshold: .high), now: now)
            try await maintenance.backup()

            let backup = try await RegistrationStore.open(path: backupPath)
            let deletedSurvives = try await backup.registration(token: testToken(1))
            let current = try await backup.registration(token: testToken(2))
            try await backup.close()
            #expect(deletedSurvives == nil)
            #expect(current?.zone == "KEV")

            let siblings = try FileManager.default.contentsOfDirectory(atPath: (backupPath as NSString).deletingLastPathComponent)
            let name = (backupPath as NSString).lastPathComponent
            #expect(siblings.filter { $0.hasPrefix(name) } == [name])
        }
    }

    @Test func runsAtNextNightlyTime() {
        #expect(Maintenance.nextRun(after: utc("2026-11-03T20:15:00Z")) == utc("2026-11-04T03:00:00Z"))
        #expect(Maintenance.nextRun(after: utc("2026-11-04T02:59:59Z")) == utc("2026-11-04T03:00:00Z"))
        #expect(Maintenance.nextRun(after: utc("2026-11-04T03:00:00Z")) == utc("2026-11-05T03:00:00Z"))
    }

    @Test func backupPathIsNextToDatabase() throws {
        let configuration = try Configuration(environment: [
            "APNS_KEY_ID": "ABC123DEFG", "APNS_TEAM_ID": "TEAM123456", "APNS_KEY_PATH": "/run/secrets/apns_key",
            "APNS_TOPIC": "fi.juusimaa.revontulet", "DATABASE_PATH": "/data/alerts.db",
        ])
        #expect(configuration.backupPath == "/data/alerts-backup.db")
    }
}
