import Foundation
import Synchronization
import Testing
@testable import AuroraCore

/// Records calls and answers with a configurable failure.
final class FakeAlertAPI: AlertAPI {
    enum Call: Equatable, Sendable {
        case upsert(RegistrationUpsert)
        case delete(String)
        case test(String)
    }

    private let state = Mutex<(calls: [Call], failure: AlertAPIFailure?)>(([], nil))

    var calls: [Call] { state.withLock { $0.calls } }

    /// Every following call fails with `failure` (nil: succeeds).
    func fail(with failure: AlertAPIFailure?) {
        state.withLock { $0.failure = failure }
    }

    private func record(_ call: Call) throws(AlertAPIFailure) {
        let failure = state.withLock { state in
            state.calls.append(call)
            return state.failure
        }
        if let failure { throw failure }
    }

    func upsert(_ registration: RegistrationUpsert) async throws(AlertAPIFailure) { try record(.upsert(registration)) }
    func delete(_ token: RegistrationToken) async throws(AlertAPIFailure) { try record(.delete(token.token)) }
    func sendTest(_ token: RegistrationToken) async throws(AlertAPIFailure) { try record(.test(token.token)) }
}

actor InMemoryAlertSyncStore: AlertSyncStore {
    private(set) var saved: AlertSyncState?

    init(_ state: AlertSyncState? = nil) {
        saved = state
    }

    func load() -> AlertSyncState { saved ?? AlertSyncState() }
    func save(_ state: AlertSyncState) { saved = state }
}

/// A clock the test moves by hand.
final class ManualClock: Sendable {
    private let value: Mutex<Date>

    init(_ start: Date) { value = Mutex(start) }

    var now: Date { value.withLock { $0 } }

    func advance(_ seconds: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

@Suite("Alert sync")
struct AlertSyncTests {
    static let token = String(repeating: "a1", count: 32)
    static let newToken = String(repeating: "b2", count: 32)

    let api = FakeAlertAPI()
    let store = InMemoryAlertSyncStore()
    let clock = ManualClock(utc("2026-11-03T18:00:00Z"))

    func makeSync() -> AlertSync {
        AlertSync(api: api, store: store, now: { [clock] in clock.now })
    }

    /// Token known, zone OUJ known, nothing sent yet.
    func readySync() async -> AlertSync {
        let sync = makeSync()
        await sync.tokenChanged(Self.token)
        await sync.zoneChanged(to: "OUJ")
        return sync
    }

    // MARK: Enabling

    @Test func enablingSendsOneUpsert() async {
        let sync = await readySync()
        #expect(api.calls.isEmpty)

        await sync.setDesired(.enabled(zone: "OUJ", threshold: .moderate))

        #expect(api.calls == [.upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .moderate))])
        let state = await sync.state
        #expect(state.confirmed == .enabled(zone: "OUJ", threshold: .moderate))
        #expect(state.confirmedAt == clock.now)
        #expect(!state.isPending)
        #expect(state.isOn)
    }

    @Test func enablingWithoutTokenWaitsForIt() async {
        let sync = makeSync()
        await sync.zoneChanged(to: "OUJ")

        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))
        #expect(api.calls.isEmpty)
        #expect(await sync.state.isPending)

        await sync.tokenChanged(Self.token)
        #expect(api.calls == [.upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .high))])
        #expect(await !sync.state.isPending)
    }

    @Test func stateIsSaved() async {
        let sync = await readySync()
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        let saved = await store.saved
        #expect(saved?.desired == .enabled(zone: "OUJ", threshold: .high))
        #expect(saved?.confirmed == .enabled(zone: "OUJ", threshold: .high))
        #expect(saved?.token == Self.token)
        #expect(saved?.zone == "OUJ")
        #expect(saved?.hasEverEnabled == true)
    }

    @Test func savedStateIsLoaded() async {
        let state = AlertSyncState(desired: .enabled(zone: "KEV", threshold: .high), confirmed: .enabled(zone: "KEV", threshold: .high),
                                   confirmedToken: Self.token, confirmedAt: clock.now, token: Self.token, zone: "KEV")
        let sync = AlertSync(api: api, store: InMemoryAlertSyncStore(state), now: { [clock] in clock.now })

        #expect(await sync.state == state)
        await sync.sync(now: clock.now)
        #expect(api.calls.isEmpty)
    }

    // MARK: Zone

    @Test func zoneChangeSendsUpsertWithNewZone() async {
        let sync = await readySync()
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        await sync.zoneChanged(to: "RAN")
        await sync.zoneChanged(to: "RAN")

        #expect(api.calls.dropFirst() == [.upsert(RegistrationUpsert(token: Self.token, zone: "RAN", threshold: .high))])
        #expect(await sync.state.desired == .enabled(zone: "RAN", threshold: .high))
    }

    @Test func zoneChangeWhileOffSendsNothingButIsRemembered() async {
        let sync = await readySync()

        await sync.zoneChanged(to: "KEV")
        #expect(api.calls.isEmpty)
        #expect(await sync.state.zone == "KEV")
    }

    // MARK: Token

    @Test func tokenChangeReplacesRegistration() async {
        let sync = await readySync()
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        await sync.tokenChanged(Self.newToken)

        #expect(api.calls.dropFirst() == [
            .upsert(RegistrationUpsert(token: Self.newToken, zone: "OUJ", threshold: .high)),
            .delete(Self.token),
        ])
        let state = await sync.state
        #expect(state.confirmedToken == Self.newToken)
        #expect(state.staleTokens.isEmpty)
        #expect(!state.isPending)
    }

    @Test func sameTokenAgainSendsNothing() async {
        let sync = await readySync()
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        await sync.tokenChanged(Self.token)

        #expect(api.calls.count == 1)
    }

    // MARK: Retries

    @Test func unreachableKeepsChangePendingAndRetriesOnNextSync() async {
        let sync = await readySync()
        api.fail(with: .unreachable)

        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))
        var state = await sync.state
        #expect(state.isPending)
        #expect(state.isOn)  // shown as on, "Waiting to confirm"
        #expect(state.confirmed == nil)

        api.fail(with: nil)
        clock.advance(5)
        await sync.sync(now: clock.now)

        state = await sync.state
        #expect(!state.isPending)
        #expect(api.calls.count == 2)
        #expect(api.calls.allSatisfy { $0 == .upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .high)) })
    }

    @Test func backoffWhileOpen() async {
        let sync = await readySync()
        api.fail(with: .unreachable)
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))
        #expect(api.calls.count == 1)

        // 30 s → 2 min → 10 min, then stays at 10 min.
        for (wait, attempt) in [(30.0, 2), (120, 3), (600, 4), (600, 5)] {
            clock.advance(wait - 1)
            await sync.retryIfDue(now: clock.now)
            #expect(api.calls.count == attempt - 1, "not before \(wait) s")
            clock.advance(1)
            await sync.retryIfDue(now: clock.now)
            #expect(api.calls.count == attempt, "after \(wait) s")
        }
    }

    @Test func retryIfDueDoesNothingWhenNothingPending() async {
        let sync = await readySync()
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        clock.advance(3_600)
        await sync.retryIfDue(now: clock.now)

        #expect(api.calls.count == 1)
    }

    // MARK: Re-confirmation

    @Test func reconfirmsAtMostOncePerDay() async {
        let sync = await readySync()
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))
        let upsert = FakeAlertAPI.Call.upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .high))

        clock.advance(3_600)
        await sync.sync(now: clock.now)
        #expect(api.calls == [upsert])

        clock.advance(23 * 3_600)
        await sync.sync(now: clock.now)
        #expect(api.calls == [upsert, upsert])
        #expect(await sync.state.confirmedAt == clock.now)

        clock.advance(60)
        await sync.sync(now: clock.now)
        #expect(api.calls == [upsert, upsert])
    }

    @Test func noReconfirmationWhileOff() async {
        let sync = await readySync()

        clock.advance(3 * 86_400)
        await sync.sync(now: clock.now)

        #expect(api.calls.isEmpty)
    }
}
