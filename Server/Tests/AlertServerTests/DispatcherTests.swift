import APNSCore
import AuroraCore
import Foundation
import Testing
@testable import AlertServer

@Suite("Dispatcher")
struct DispatcherTests {
    /// 22:15 Helsinki on 2026-11-03.
    private let now = utc("2026-11-03T20:15:00Z")
    private let dataTime = utc("2026-11-03T20:12:10Z")

    private func decision(_ level: ChanceLevel, zone: String = "OUJ", cloudsIncluded: Bool = true) -> AlertDecision {
        let condition = ZoneCondition(
            zoneID: zone, chance: Chance(level: level, limitingFactor: level == .high ? nil : .activity, cloudsIncluded: cloudsIncluded),
            reason: level == .high ? .goodConditions : .someActivity, activityStationID: zone, dataTime: dataTime)
        return AlertDecision(zoneID: zone, level: level, condition: condition)
    }

    private func register(_ store: RegistrationStore, _ n: Int, zone: String = "OUJ", threshold: AlertThreshold, at date: Date? = nil) async throws {
        try await store.upsert(RegistrationUpsert(token: testToken(n), zone: zone, threshold: threshold), now: date ?? now)
    }

    private func dispatcher(_ store: RegistrationStore, _ sender: FakePushSender) -> Dispatcher {
        Dispatcher(store: store, sender: sender, topic: "fi.juusimaa.revontulet")
    }

    // MARK: Recipients

    @Test func moderateGoesToModerateRegistrationsOnly() async throws {
        try await withTemporaryStore { store, _ in
            try await register(store, 1, threshold: .moderate)
            try await register(store, 2, threshold: .high)
            try await register(store, 3, zone: "KEV", threshold: .moderate)
            let sender = FakePushSender()

            let report = try await dispatcher(store, sender).dispatch([decision(.moderate)], now: now)

            #expect(sender.sent.map(\.token) == [testToken(1)])
            #expect(report == DispatchReport(sent: 1))
        }
    }

    @Test func highGoesToBothThresholds() async throws {
        try await withTemporaryStore { store, _ in
            try await register(store, 1, threshold: .moderate)
            try await register(store, 2, threshold: .high)
            let sender = FakePushSender()

            _ = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            #expect(Set(sender.sent.map(\.token)) == [testToken(1), testToken(2)])
        }
    }

    // MARK: Request

    @Test func requestHeadersAndMessage() async throws {
        try await withTemporaryStore { store, _ in
            try await register(store, 1, threshold: .high)
            let sender = FakePushSender()

            _ = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            let request = try #require(sender.sent.first)
            #expect(request.message == AlertMessage(titleKey: "alert.title.high", bodyKey: "alert.body.goodConditions", arguments: ["Oulujärvi"]))
            #expect(request.expiration == dataTime.addingTimeInterval(20 * 60))
            #expect(request.collapseID == "OUJ-high-2026-11-03")

            let apns = APNSPushSender.apnsRequest(for: request, topic: "fi.juusimaa.revontulet")
            #expect(apns.headers == [
                "apns-push-type": "alert",
                "apns-priority": "10",
                "apns-topic": "fi.juusimaa.revontulet",
                "apns-expiration": String(Int(dataTime.timeIntervalSince1970) + 1_200),
                "apns-collapse-id": "OUJ-high-2026-11-03",
            ])
            #expect(apns.deviceToken == testToken(1))
        }
    }

    @Test func payloadMatchesContract() throws {
        let request = PushRequest(
            token: testToken(1),
            message: AlertMessage(titleKey: "alert.title.high", bodyKey: "alert.body.goodConditions", arguments: ["Oulujärvi"]),
            expiration: nil, collapseID: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = String(decoding: try encoder.encode(AlertPayload(request.message)), as: UTF8.self)

        let expected = """
            {"aps":{"alert":{"loc-args":["Oulujärvi"],"loc-key":"alert.body.goodConditions","title-loc-key":"alert.title.high"},\
            "sound":"default","thread-id":"aurora-alerts"}}
            """
        #expect(json == expected)
        #expect(!json.contains("interruption-level"))
        #expect(!json.contains("badge"))
    }

    @Test func testMessagePayloadHasNoArguments() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = String(decoding: try encoder.encode(AlertPayload(AlertMessage.test)), as: UTF8.self)

        #expect(json == #"{"aps":{"alert":{"loc-key":"alert.body.test","title-loc-key":"alert.title.test"},"sound":"default","thread-id":"aurora-alerts"}}"#)
    }

    // MARK: Responses

    @Test func unregisteredDeletesRegistration() async throws {
        try await withTemporaryStore { store, _ in
            try await register(store, 1, threshold: .high, at: utc("2026-10-01T12:00:00Z"))
            let sender = FakePushSender()
            sender.respond(testToken(1), with: .unregistered(timestamp: utc("2026-11-02T09:00:00Z")))

            let report = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            #expect(try await store.registration(token: testToken(1)) == nil)
            #expect(report == DispatchReport(sent: 0, deleted: 1))
        }
    }

    @Test func unregisteredKeepsRegistrationConfirmedThatDay() async throws {
        try await withTemporaryStore { store, _ in
            // Re-registered on 2026-11-02, the UTC day of the 410's timestamp: kept.
            try await register(store, 1, threshold: .high, at: utc("2026-11-02T23:00:00Z"))
            let sender = FakePushSender()
            sender.respond(testToken(1), with: .unregistered(timestamp: utc("2026-11-02T09:00:00Z")))

            _ = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            #expect(try await store.registration(token: testToken(1)) != nil)
        }
    }

    @Test func badDeviceTokenDeletes() async throws {
        try await withTemporaryStore { store, _ in
            for n in 1...20 { try await register(store, n, threshold: .high) }
            let sender = FakePushSender()
            sender.respond(testToken(3), with: .badDeviceToken)

            let report = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            #expect(try await store.registration(token: testToken(3)) == nil)
            #expect(try await store.registrations(inZone: "OUJ").count == 19)
            #expect(report == DispatchReport(sent: 19, deleted: 1))
        }
    }

    @Test func manyBadTokensTripTheCircuitBreaker() async throws {
        try await withTemporaryStore { store, _ in
            for n in 1...30 { try await register(store, n, threshold: .high) }
            let sender = FakePushSender()
            sender.respondToAll(with: .badDeviceToken)

            let report = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            // Stops at the 11th bad token and deletes nothing.
            #expect(sender.sent.count == 11)
            #expect(try await store.registrations(inZone: "OUJ").count == 30)
            #expect(report.failure == .badDeviceTokens)
            #expect(report.deleted == 0)
        }
    }

    @Test func circuitBreakerScalesWithTenPercent() async throws {
        try await withTemporaryStore { store, _ in
            for n in 1...200 { try await register(store, n, threshold: .high) }
            let sender = FakePushSender()
            for n in 1...15 { sender.respond(testToken(n), with: .badDeviceToken) }

            let report = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            // 15 of 200 is under 10 %: deleted.
            #expect(report.failure == nil)
            #expect(report.deleted == 15)
            #expect(try await store.registrations(inZone: "OUJ").count == 185)
        }
    }

    @Test func providerTokenErrorStopsAndFails() async throws {
        try await withTemporaryStore { store, _ in
            for n in 1...5 { try await register(store, n, threshold: .high) }
            let sender = FakePushSender()
            sender.respondToAll(with: .providerTokenRejected)

            let report = try await dispatcher(store, sender).dispatch([decision(.high), decision(.high, zone: "KEV")], now: now)

            #expect(sender.sent.count == 1)
            #expect(report.failure == .providerToken)
            #expect(try await store.registrations(inZone: "OUJ").count == 5)
        }
    }

    @Test func retryableIsRetriedOnceThenDropped() async throws {
        try await withTemporaryStore { store, _ in
            try await register(store, 1, threshold: .high)
            try await register(store, 2, threshold: .high)
            let sender = FakePushSender()
            sender.respond(testToken(1), with: .retryable, .delivered)
            sender.respond(testToken(2), with: .retryable)

            let report = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            #expect(sender.sent.filter { $0.token == testToken(1) }.count == 2)
            #expect(sender.sent.filter { $0.token == testToken(2) }.count == 2)
            #expect(report == DispatchReport(sent: 1, dropped: 1))
            #expect(try await store.registrations(inZone: "OUJ").count == 2)
        }
    }

    @Test func noRegistrationsSendsNothing() async throws {
        try await withTemporaryStore { store, _ in
            let sender = FakePushSender()

            let report = try await dispatcher(store, sender).dispatch([decision(.high)], now: now)

            #expect(sender.sent.isEmpty)
            #expect(report == DispatchReport())
        }
    }
}
