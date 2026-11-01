import AuroraCore
import Foundation
import Synchronization
import Testing
@testable import AlertServer

/// Returns scripted conditions per cycle, or fails like FMI being unreachable.
final class StubConditionSource: ZoneConditionSource {
    private let script = Mutex<(conditions: [ZoneCondition], offline: Bool)>(([], false))

    func set(_ conditions: [ZoneCondition], offline: Bool = false) {
        script.withLock { $0 = (conditions, offline) }
    }

    func evaluate(at date: Date) async throws -> [ZoneCondition] {
        let (conditions, offline) = script.withLock { $0 }
        if offline { throw AuroraServiceError.offline }
        return conditions
    }
}

@Suite("Evaluation loop")
struct EvaluationLoopTests {
    /// 22:00 Helsinki.
    private let evening = utc("2026-11-03T20:00:00Z")

    private func condition(_ level: ChanceLevel, zone: String = "OUJ", at now: Date, ageMinutes: Double = 2) -> ZoneCondition {
        ZoneCondition(
            zoneID: zone, chance: Chance(level: level, limitingFactor: level == .high ? nil : .activity, cloudsIncluded: true),
            reason: level == .high ? .goodConditions : level == .moderate ? .someActivity : .lowActivity,
            activityStationID: zone, dataTime: now.addingTimeInterval(-ageMinutes * 60))
    }

    private func makeLoop(source: any ZoneConditionSource, store: RegistrationStore, sender: FakePushSender,
                          heartbeat: FakeHeartbeat, health: HealthStatus = HealthStatus()) -> EvaluationLoop {
        EvaluationLoop(source: source, store: store, dispatcher: Dispatcher(store: store, sender: sender, topic: "fi.juusimaa.revontulet"),
                       health: health, heartbeat: heartbeat)
    }

    @Test func decisionsAreDispatchedInTheSameCycle() async throws {
        try await withTemporaryStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: testToken(1), zone: "OUJ", threshold: .moderate), now: evening)
            let source = StubConditionSource()
            let sender = FakePushSender()
            let heartbeat = FakeHeartbeat()
            let loop = makeLoop(source: source, store: store, sender: sender, heartbeat: heartbeat)

            source.set([condition(.moderate, at: evening), condition(.low, zone: "KEV", at: evening)])
            let outcome = await loop.runCycle(now: evening)

            #expect(outcome == .success(alerts: 1))
            #expect(sender.sent.map(\.token) == [testToken(1)])
            #expect(sender.sent.first?.message.bodyKey == "alert.body.someActivity")
            #expect(heartbeat.recorded == [true])
        }
    }

    @Test func stateIsPersistedAfterEachCycle() async throws {
        try await withTemporaryStore { store, _ in
            let source = StubConditionSource()
            let loop = makeLoop(source: source, store: store, sender: FakePushSender(), heartbeat: FakeHeartbeat())

            source.set([condition(.high, at: evening)])
            _ = await loop.runCycle(now: evening)

            let states = try await store.zoneStates(as: ZoneAlertState.self)
            #expect(states["OUJ"]?.alertedLevels == [.moderate, .high])
            #expect(states["OUJ"]?.alertsTonight == 1)
            #expect(states["OUJ"]?.night == "2026-11-03")
        }
    }

    @Test func restartDoesNotResendAndSendsNothingStale() async throws {
        try await withTemporaryStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: testToken(1), zone: "OUJ", threshold: .moderate), now: evening)
            let source = StubConditionSource()
            let sender = FakePushSender()

            let first = makeLoop(source: source, store: store, sender: sender, heartbeat: FakeHeartbeat())
            source.set([condition(.high, at: evening)])
            _ = await first.runCycle(now: evening)
            #expect(sender.sent.count == 1)

            // Restart 40 minutes later: the same High is not sent again.
            let restarted = makeLoop(source: source, store: store, sender: sender, heartbeat: FakeHeartbeat())
            let later = evening.addingTimeInterval(40 * 60)
            source.set([condition(.high, at: later)])
            _ = await restarted.runCycle(now: later)
            #expect(sender.sent.count == 1)

            // A zone that rose while the service was down, with stale data, is not alerted (FR-009).
            source.set([condition(.high, zone: "KEV", at: later, ageMinutes: 45)])
            try await store.upsert(RegistrationUpsert(token: testToken(2), zone: "KEV", threshold: .high), now: evening)
            _ = await restarted.runCycle(now: later)
            #expect(sender.sent.count == 1)
        }
    }

    @Test func fmiUnavailableIsNotASuccess() async throws {
        try await withTemporaryStore { store, _ in
            let source = StubConditionSource()
            let heartbeat = FakeHeartbeat()
            let health = HealthStatus(now: { [evening] in evening })
            let loop = makeLoop(source: source, store: store, sender: FakePushSender(), heartbeat: heartbeat, health: health)

            source.set([], offline: true)
            let outcome = await loop.runCycle(now: evening)

            #expect(outcome == .fmiUnavailable)
            #expect(heartbeat.recorded.isEmpty)
            #expect(await !health.isHealthy)
        }
    }

    @Test func successfulCycleMarksHealthy() async throws {
        try await withTemporaryStore { store, _ in
            let source = StubConditionSource()
            let health = HealthStatus(now: { [evening] in evening })
            let loop = makeLoop(source: source, store: store, sender: FakePushSender(), heartbeat: FakeHeartbeat(), health: health)

            source.set([])
            #expect(await loop.runCycle(now: evening) == .success(alerts: 0))
            #expect(await health.isHealthy)
        }
    }

    @Test func configurationFailurePingsFailAndKeepsState() async throws {
        try await withTemporaryStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: testToken(1), zone: "OUJ", threshold: .high), now: evening)
            let source = StubConditionSource()
            let sender = FakePushSender()
            sender.respondToAll(with: .providerTokenRejected)
            let heartbeat = FakeHeartbeat()
            let loop = makeLoop(source: source, store: store, sender: sender, heartbeat: heartbeat)

            source.set([condition(.high, at: evening)])
            let outcome = await loop.runCycle(now: evening)

            #expect(outcome == .dispatchFailed)
            #expect(heartbeat.recorded == [false])
            // Not marked as sent: the alert is tried again next cycle while the data is fresh.
            #expect(try await store.zoneStates(as: ZoneAlertState.self)["OUJ"] == nil)

            sender.respondToAll(with: .delivered)
            let next = evening.addingTimeInterval(300)
            source.set([condition(.high, at: next)])
            #expect(await loop.runCycle(now: next) == .success(alerts: 1))
            #expect(heartbeat.recorded == [false, true])
        }
    }

    @Test func zonesWithoutConditionKeepTheirState() async throws {
        try await withTemporaryStore { store, _ in
            let source = StubConditionSource()
            let loop = makeLoop(source: source, store: store, sender: FakePushSender(), heartbeat: FakeHeartbeat())

            source.set([condition(.high, at: evening)])
            _ = await loop.runCycle(now: evening)
            source.set([])
            _ = await loop.runCycle(now: evening.addingTimeInterval(300))

            let states = try await store.zoneStates(as: ZoneAlertState.self)
            #expect(states["OUJ"]?.alertedLevels == [.moderate, .high])
        }
    }

    /// The strong recorded night, replayed through the real evaluator, policy and dispatcher,
    /// sends exactly the alerts in its expected.json.
    @Test func strongNightReplayMatchesExpected() async throws {
        let http = try NightReplayHTTPClient(night: "20261014")
        try await withTemporaryStore { store, _ in
            let zones = try AlertZones.all()
            for (n, zone) in zones.enumerated() {
                try await store.upsert(RegistrationUpsert(token: testToken(n + 1), zone: zone.id, threshold: .moderate), now: http.start)
            }
            let sender = FakePushSender()
            let loop = makeLoop(source: try ZoneEvaluator(http: http), store: store, sender: sender, heartbeat: FakeHeartbeat())

            var alerts: [NightReplayHTTPClient.Expected] = []
            for now in http.cycles {
                let before = sender.sent.count
                _ = await loop.runCycle(now: now)
                for request in sender.sent[before...] {
                    let zone = zones[Int(request.token, radix: 16)! - 1].id
                    let level = request.message.titleKey == "alert.title.high" ? "high" : "moderate"
                    alerts.append(.init(zone: zone, level: level, time: ISO8601DateFormatter().string(from: now)))
                }
            }

            #expect(Set(alerts) == Set(http.expected))
            #expect(alerts.count == http.expected.count)
        }
    }

    /// FR-025 of spec 003: the alert service never uses NOAA. Its only data source is the core's
    /// `ZoneEvaluator`; any request to SWPC fails the test.
    @Test func makesNoNOAARequests() async throws {
        let http = NOAAGuardHTTPClient(base: try NightReplayHTTPClient(night: "20261014"))
        try await withTemporaryStore { store, _ in
            try await store.upsert(RegistrationUpsert(token: testToken(1), zone: "KEV", threshold: .moderate), now: http.base.start)
            let loop = makeLoop(source: try ZoneEvaluator(http: http), store: store, sender: FakePushSender(),
                                heartbeat: FakeHeartbeat())
            for now in http.base.cycles.prefix(24) {
                _ = await loop.runCycle(now: now)
            }
        }
        #expect(http.requests.count > 0)
        #expect(http.requests.allSatisfy { $0.host == "opendata.fmi.fi" })
    }
}

/// Records every request and fails the test on any request to NOAA SWPC.
final class NOAAGuardHTTPClient: HTTPClient {
    let base: NightReplayHTTPClient
    private let requested = Mutex<[URL]>([])

    init(base: NightReplayHTTPClient) {
        self.base = base
    }

    var requests: [URL] { requested.withLock { $0 } }

    func get(_ url: URL) async throws -> (Data, Int) {
        requested.withLock { $0.append(url) }
        if url.host == "services.swpc.noaa.gov" {
            Issue.record("The alert service requested \(url)")
            return (Data(), 500)
        }
        return try await base.get(url)
    }
}
