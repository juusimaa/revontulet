import AuroraCore
import Foundation
import Testing
@testable import AlertServer

@Suite("Registration store")
struct RegistrationStoreTests {
    private let token1 = String(repeating: "a1", count: 32)
    private let token2 = String(repeating: "b2", count: 32)
    // 2026-10-25 21:47:13 UTC; the day starts at 1761350400.
    private let now = Date(timeIntervalSince1970: 1_761_428_833)
    private let startOfDay = Date(timeIntervalSince1970: 1_761_350_400)

    /// Runs `body` with a store on a fresh temporary database file, then removes the file.
    private func withStore(_ body: (RegistrationStore, String) async throws -> Void) async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("alerts-\(UUID().uuidString).db").path
        let store = try await RegistrationStore.open(path: path)
        do {
            try await body(store, path)
            try await store.close()
        } catch {
            try? await store.close()
            try? FileManager.default.removeItem(atPath: path)
            throw error
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test func upsertStoresRegistrationWithDayPrecision() async throws {
        try await withStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: token1, zone: "OUJ", threshold: .moderate), now: now)

            let stored = try await store.registration(token: token1)
            #expect(stored == Registration(token: token1, zone: "OUJ", threshold: .moderate, confirmedAt: startOfDay))
        }
    }

    @Test func upsertReplacesExistingRegistration() async throws {
        try await withStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: token1, zone: "OUJ", threshold: .moderate), now: now)
            let later = now.addingTimeInterval(3 * 86_400)
            try await store.upsert(RegistrationUpsert(token: token1, zone: "KEV", threshold: .high), now: later)

            #expect(try await store.registrations(inZone: "OUJ").isEmpty)
            let stored = try await store.registrations(inZone: "KEV")
            #expect(stored == [Registration(token: token1, zone: "KEV", threshold: .high,
                                            confirmedAt: startOfDay.addingTimeInterval(3 * 86_400))])
        }
    }

    @Test func registrationsInZone() async throws {
        try await withStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: token1, zone: "OUJ", threshold: .moderate), now: now)
            try await store.upsert(RegistrationUpsert(token: token2, zone: "OUJ", threshold: .high), now: now)
            try await store.upsert(RegistrationUpsert(token: String(repeating: "c3", count: 32), zone: "KEV", threshold: .high), now: now)

            let tokens = try await store.registrations(inZone: "OUJ").map(\.token).sorted()
            #expect(tokens == [token1, token2])
            #expect(try await store.registrations(inZone: "TAR").isEmpty)
        }
    }

    @Test func deleteRemovesRegistrationAndIsIdempotent() async throws {
        try await withStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: token1, zone: "OUJ", threshold: .high), now: now)

            try await store.delete(token: token1)
            try await store.delete(token: token1)

            #expect(try await store.registration(token: token1) == nil)
        }
    }

    @Test func deleteConfirmedBefore() async throws {
        try await withStore { store, _ in
            let old = now.addingTimeInterval(-181 * 86_400)
            try await store.upsert(RegistrationUpsert(token: token1, zone: "OUJ", threshold: .high), now: old)
            try await store.upsert(RegistrationUpsert(token: token2, zone: "OUJ", threshold: .high), now: now)

            let deleted = try await store.deleteConfirmed(before: now.addingTimeInterval(-180 * 86_400))

            #expect(deleted == 1)
            #expect(try await store.registration(token: token1) == nil)
            #expect(try await store.registration(token: token2) != nil)
        }
    }

    @Test func zoneStateRoundTripsAndPersists() async throws {
        struct State: Codable, Equatable { var night: String; var alertsTonight: Int }
        try await withStore { store, path in
            try await store.saveZoneState(State(night: "2026-10-25", alertsTonight: 1), zone: "OUJ")
            try await store.saveZoneState(State(night: "2026-10-25", alertsTonight: 2), zone: "OUJ")
            try await store.saveZoneState(State(night: "2026-10-24", alertsTonight: 3), zone: "KEV")

            let reopened = try await RegistrationStore.open(path: path)
            let states = try await reopened.zoneStates(as: State.self)
            try await reopened.close()

            #expect(states == ["OUJ": State(night: "2026-10-25", alertsTonight: 2),
                               "KEV": State(night: "2026-10-24", alertsTonight: 3)])
        }
    }

    @Test func schemaHasOnlyTheDocumentedColumns() async throws {
        try await withStore { store, _ in
            let registrations = try await store.columns(of: "registrations")
            let zoneState = try await store.columns(of: "zone_alert_state")
            #expect(registrations == ["token", "zone", "threshold", "confirmed_at"])
            #expect(zoneState == ["zone", "state"])
        }
    }
}
