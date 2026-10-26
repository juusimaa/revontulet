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

    // MARK: Disabling

    /// On and confirmed with OUJ/high.
    func enabledSync() async -> AlertSync {
        let sync = await readySync()
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))
        return sync
    }

    @Test func disablingShowsOffAtOnceAndSendsDelete() async {
        let sync = await enabledSync()

        await sync.setDesired(.disabled)

        #expect(api.calls.dropFirst() == [.delete(Self.token)])
        let state = await sync.state
        #expect(state.desired == .disabled)
        #expect(!state.isOn)
        #expect(!state.isPending)
        #expect(state.confirmed == .disabled)
        #expect(state.threshold == .high)  // kept for turning on again
    }

    @Test func deleteIsRetriedUntilConfirmed() async {
        let sync = await enabledSync()
        api.fail(with: .unreachable)

        await sync.setDesired(.disabled)
        var state = await sync.state
        #expect(!state.isOn)  // off at once, "Removing…"
        #expect(state.isPending)

        clock.advance(30)
        await sync.retryIfDue(now: clock.now)
        clock.advance(5)
        await sync.sync(now: clock.now)
        #expect(await sync.state.isPending)

        api.fail(with: nil)
        clock.advance(5)
        await sync.sync(now: clock.now)

        state = await sync.state
        #expect(!state.isPending)
        #expect(Array(api.calls.dropFirst()) == Array(repeating: FakeAlertAPI.Call.delete(Self.token), count: 4))

        clock.advance(3 * 86_400)
        await sync.sync(now: clock.now)
        #expect(api.calls.count == 5)
    }

    @Test func disablingBeforeConfirmationStillDeletes() async {
        let sync = await readySync()
        api.fail(with: .unreachable)
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        api.fail(with: nil)
        await sync.setDesired(.disabled)

        #expect(api.calls.last == .delete(Self.token))
        #expect(await !sync.state.isPending)
    }

    @Test func disablingUnconfirmedWhileUnreachableIsPending() async {
        let sync = await readySync()
        api.fail(with: .unreachable)
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        await sync.setDesired(.disabled)
        #expect(api.calls.last == .delete(Self.token))
        #expect(await sync.state.isPending)  // "Removing…": the upsert may have arrived

        api.fail(with: nil)
        await sync.sync(now: clock.now)
        #expect(await !sync.state.isPending)
    }

    @Test func disablingBeforeAnyTokenIsNotPending() async {
        let sync = makeSync()
        await sync.zoneChanged(to: "OUJ")
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))

        await sync.setDesired(.disabled)

        #expect(api.calls.isEmpty)
        #expect(await !sync.state.isPending)
    }

    @Test func turningOnAgainWhileRemovingSendsUpsert() async {
        let sync = await enabledSync()
        api.fail(with: .unreachable)
        await sync.setDesired(.disabled)

        api.fail(with: nil)
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .moderate))

        #expect(api.calls.last == .upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .moderate)))
        let state = await sync.state
        #expect(state.isOn)
        #expect(!state.isPending)
    }

    // MARK: Threshold

    @Test func thresholdChangeSendsOneUpsert() async {
        let sync = await enabledSync()

        await sync.setDesired(.enabled(zone: "OUJ", threshold: .moderate))
        await sync.sync(now: clock.now)

        #expect(api.calls.dropFirst() == [.upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .moderate))])
        let state = await sync.state
        #expect(state.threshold == .moderate)
        #expect(!state.isPending)
    }

    // MARK: Service answers

    @Test func rejectedChangeIsNotRetried() async {
        let sync = await readySync()
        api.fail(with: .rejected(.invalidZone))

        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))
        #expect(await sync.state.rejection == .invalidZone)

        api.fail(with: nil)
        for _ in 0..<3 {
            clock.advance(600)
            await sync.retryIfDue(now: clock.now)
            await sync.sync(now: clock.now)
        }
        #expect(api.calls.count == 1)
        #expect(await sync.state.isPending)

        // A different change is sent.
        await sync.setDesired(.enabled(zone: "OUJ", threshold: .moderate))
        #expect(api.calls.count == 2)
        #expect(await sync.state.rejection == nil)
    }

    @Test func rateLimitedWaitsForRetryAfter() async {
        let sync = await readySync()
        api.fail(with: .rateLimited(retryAfter: 300))

        await sync.setDesired(.enabled(zone: "OUJ", threshold: .high))
        api.fail(with: nil)

        clock.advance(299)
        await sync.sync(now: clock.now)
        await sync.retryIfDue(now: clock.now)
        #expect(api.calls.count == 1)

        clock.advance(1)
        await sync.retryIfDue(now: clock.now)
        #expect(api.calls.count == 2)
        #expect(await !sync.state.isPending)
    }

    // MARK: Permission revoked

    @Test func permissionRevokedWhileOnDeletesAndDisables() async {
        let sync = await enabledSync()

        await sync.permissionRevoked()

        #expect(api.calls.dropFirst() == [.delete(Self.token)])
        let state = await sync.state
        #expect(state.desired == .disabled)
        #expect(!state.isOn)
        #expect(!state.isPending)
    }

    @Test func permissionRevokedWhileOffSendsNothing() async {
        let sync = await readySync()

        await sync.permissionRevoked()

        #expect(api.calls.isEmpty)
        #expect(await sync.state.desired == .disabled)
    }

    // MARK: Test notification

    @Test func sendTestSendsToCurrentToken() async {
        let sync = await enabledSync()

        let result = await sync.sendTest()

        #expect(result == .sent)
        #expect(api.calls.last == .test(Self.token))
    }

    @Test func sendTestNotRegisteredReRegisters() async {
        let sync = await enabledSync()
        api.fail(with: .notRegistered)

        let result = await sync.sendTest()

        #expect(result == .notRegistered)
        #expect(api.calls.dropFirst() == [.test(Self.token), .upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .high))])
        api.fail(with: nil)
        await sync.sync(now: clock.now)
        #expect(api.calls.last == .upsert(RegistrationUpsert(token: Self.token, zone: "OUJ", threshold: .high)))
        #expect(await !sync.state.isPending)
    }

    @Test func sendTestRateLimitedGivesTimeToTryAgain() async {
        let sync = await enabledSync()
        api.fail(with: .rateLimited(retryAfter: 1_500))

        let result = await sync.sendTest()

        #expect(result == .rateLimited(until: clock.now.addingTimeInterval(1_500)))
        #expect(api.calls.dropFirst() == [.test(Self.token)])
    }

    @Test func sendTestUnreachableFails() async {
        let sync = await enabledSync()
        api.fail(with: .unreachable)

        #expect(await sync.sendTest() == .failed)
    }

    @Test func sendTestWhileOffSendsNothing() async {
        let sync = await readySync()

        #expect(await sync.sendTest() == .failed)
        #expect(api.calls.isEmpty)
    }
}
