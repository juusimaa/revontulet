import Foundation

/// The alert service's HTTP API as the device sees it (contracts/alert-api.md).
public protocol AlertAPI: Sendable {
    func upsert(_ registration: RegistrationUpsert) async throws(AlertAPIFailure)
    func delete(_ token: RegistrationToken) async throws(AlertAPIFailure)
    func sendTest(_ token: RegistrationToken) async throws(AlertAPIFailure)
}

public enum AlertAPIFailure: Error, Sendable, Equatable {
    /// No response or a 5xx: retried.
    case unreachable
    /// 400: not retried until the change differs.
    case rejected(AlertAPIError)
    /// 429: wait this many seconds.
    case rateLimited(retryAfter: TimeInterval)
    /// 404 from the test endpoint: the registration does not exist.
    case notRegistered
}

/// The outcome of "Send test" (US3).
public enum AlertTestResult: Sendable, Equatable {
    /// Handed to APNs; it should arrive within a minute.
    case sent
    /// Too many tests in the past hour; the user may try again at this time.
    case rateLimited(until: Date)
    /// The service had no registration; it has been re-sent and the user may try again.
    case notRegistered
    /// Alerts are off, there is no token yet, or the service could not be reached.
    case failed
}

/// What the device wants versus what the service has confirmed (data-model.md). Stored on the
/// device only.
public struct AlertSyncState: Sendable, Hashable, Codable {
    public enum Desired: Sendable, Hashable, Codable {
        case enabled(zone: AlertZone.ID, threshold: AlertThreshold)
        case disabled
    }

    /// What the user set.
    public var desired: Desired
    /// The last state the service acknowledged for `confirmedToken`; nil when unknown.
    public var confirmed: Desired?
    /// The token the service has the `confirmed` registration for.
    public var confirmedToken: String?
    /// When the service last confirmed; for the once-a-day re-confirmation (FR-014).
    public var confirmedAt: Date?
    /// The latest APNs token.
    public var token: String?
    /// The latest zone from the main screen; nil until a place in Finland has been resolved.
    public var zone: AlertZone.ID?
    /// The threshold last chosen, kept while alerts are off.
    public var threshold: AlertThreshold
    /// Replaced tokens whose registrations still have to be deleted.
    public var staleTokens: [String]
    /// Whether alerts have ever been turned on, for the first-time explanation.
    public var hasEverEnabled: Bool
    /// The service rejected the current change (400); it is not retried until the change differs.
    public var rejection: AlertAPIError?

    public init(
        desired: Desired = .disabled, confirmed: Desired? = nil, confirmedToken: String? = nil, confirmedAt: Date? = nil,
        token: String? = nil, zone: AlertZone.ID? = nil, threshold: AlertThreshold = .default, staleTokens: [String] = [],
        hasEverEnabled: Bool = false, rejection: AlertAPIError? = nil
    ) {
        self.desired = desired
        self.confirmed = confirmed
        self.confirmedToken = confirmedToken
        self.confirmedAt = confirmedAt
        self.token = token
        self.zone = zone
        self.threshold = threshold
        self.staleTokens = staleTokens
        self.hasEverEnabled = hasEverEnabled
        self.rejection = rejection
    }

    /// Alerts are shown as on as soon as the user turns them on, and as off as soon as they turn
    /// them off (FR-006), whatever the service has confirmed.
    public var isOn: Bool {
        if case .enabled = desired { true } else { false }
    }

    /// Something the service has not confirmed yet ("Waiting to confirm").
    public var isPending: Bool {
        if !staleTokens.isEmpty { return true }
        switch desired {
        case .enabled: return confirmed != desired || confirmedToken != token
        case .disabled:
            // An unconfirmed upsert may still have arrived once there was a token to send it with.
            return confirmed != .disabled && (confirmed != nil || (hasEverEnabled && (confirmedToken ?? token) != nil))
        }
    }
}

/// Where `AlertSync` keeps its state; UserDefaults in the app.
public protocol AlertSyncStore: Sendable {
    func load() async -> AlertSyncState
    func save(_ state: AlertSyncState) async
}

/// Keeps the service's registration in step with what the user set (FR-005, FR-006, FR-014).
///
/// Every change is sent at once. Failures are retried on every `sync` (app foreground) and, while
/// the app is open, by `retryIfDue` with backoff 30 s → 2 min → 10 min. No failure is ever
/// thrown to the caller; the state shows what is pending.
public actor AlertSync {
    static let backoff: [TimeInterval] = [30, 120, 600]
    static let reconfirmAfter: TimeInterval = 86_400

    private let api: any AlertAPI
    private let store: any AlertSyncStore
    private let now: @Sendable () -> Date
    private var loaded: AlertSyncState?
    private var failures = 0
    private var retryNotBefore: Date?
    private var rateLimitedUntil: Date?
    private var loading: Task<AlertSyncState, Never>?
    /// The send in progress, if any.
    private var sending: Task<Void, Never>?
    /// A send asked for while one ran: the latest time it was asked for.
    private var rerunAt: Date?

    public init(api: any AlertAPI, store: any AlertSyncStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        self.store = store
        self.now = now
    }

    public var state: AlertSyncState {
        get async { await current() }
    }

    /// Turns alerts on (with a zone and threshold), changes the threshold, or turns them off.
    public func setDesired(_ desired: AlertSyncState.Desired) async {
        var state = await current()
        state.desired = desired
        if case .enabled(let zone, let threshold) = desired {
            state.zone = zone
            state.threshold = threshold
            state.hasEverEnabled = true
        }
        state.rejection = nil
        await update(state)
        await send(now: now())
    }

    /// Notifications are no longer allowed for the app (research R7): turns alerts off and deletes
    /// the registration, as if the user had turned them off. Turning notifications back on does
    /// not turn alerts back on.
    public func permissionRevoked() async {
        guard await current().isOn else { return }
        await setDesired(.disabled)
    }

    /// The main screen resolved a place in `zone` (FR-004).
    public func zoneChanged(to zone: AlertZone.ID) async {
        var state = await current()
        guard state.zone != zone else { return }
        state.zone = zone
        if case .enabled(_, let threshold) = state.desired {
            state.desired = .enabled(zone: zone, threshold: threshold)
            state.rejection = nil
        }
        await update(state)
        await send(now: now())
    }

    /// APNs gave a token; a changed token is a new registration and the old one is deleted.
    public func tokenChanged(_ token: String) async {
        var state = await current()
        guard state.token != token else { return }
        if let old = state.confirmedToken, old != token, !state.staleTokens.contains(old) {
            state.staleTokens.append(old)
        }
        state.token = token
        state.rejection = nil
        await update(state)
        await send(now: now())
    }

    /// Sends what is pending and re-confirms when the last confirmation is a day old. Call on
    /// every foreground; it does not wait for the backoff.
    public func sync(now: Date) async {
        retryNotBefore = nil
        await send(now: now)
    }

    /// Retries a pending change once its backoff has passed. Call periodically while open.
    public func retryIfDue(now: Date) async {
        if let retryNotBefore, now < retryNotBefore { return }
        await send(now: now)
    }

    /// Asks the service for a test notification to the current token (FR-012). A missing
    /// registration is re-sent at once.
    public func sendTest() async -> AlertTestResult {
        let state = await current()
        guard state.isOn, let token = state.token else { return .failed }
        do {
            try await api.sendTest(RegistrationToken(token: token))
            return .sent
        } catch {
            switch error {
            case .rateLimited(let retryAfter):
                return .rateLimited(until: now().addingTimeInterval(retryAfter))
            case .notRegistered:
                // Re-read: other changes may have arrived while the request was out.
                var state = await current()
                state.confirmed = nil
                state.confirmedAt = nil
                await update(state)
                retryNotBefore = nil
                await send(now: now())
                return .notRegistered
            case .unreachable, .rejected:
                return .failed
            }
        }
    }

    // MARK: Sending

    /// Runs one send at a time, so requests reach the service in the order of the changes.
    /// A send asked for while one runs is folded into a rerun once it ends.
    private func send(now: Date) async {
        if let running = sending {
            rerunAt = max(rerunAt ?? now, now)
            await running.value
            return
        }
        let task = Task { await sendUntilSettled(from: now) }
        sending = task
        await task.value
    }

    private func sendUntilSettled(from now: Date) async {
        var date = now
        while true {
            rerunAt = nil
            await sendOnce(now: date)
            guard let next = rerunAt else { break }
            date = next
        }
        // No await between the last check of `rerunAt` and this, so no request is missed.
        sending = nil
    }

    /// Other calls change the state while a request is out (the actor is reentrant), so every
    /// write after a request re-reads the current state and records only what the service
    /// confirmed; a change made meanwhile is sent by the rerun.
    private func sendOnce(now: Date) async {
        if let rateLimitedUntil, now < rateLimitedUntil { return }
        let snapshot = await current()

        do {
            switch snapshot.desired {
            case .enabled(let zone, let threshold):
                guard let token = snapshot.token, snapshot.rejection == nil else { break }
                let stale = snapshot.confirmed != snapshot.desired || snapshot.confirmedToken != token
                let due = snapshot.confirmedAt.map { now.timeIntervalSince($0) >= Self.reconfirmAfter } ?? true
                if stale || due {
                    try await api.upsert(RegistrationUpsert(token: token, zone: zone, threshold: threshold))
                    var state = await current()
                    if let replaced = state.confirmedToken, replaced != token, !state.staleTokens.contains(replaced) {
                        state.staleTokens.append(replaced)
                    }
                    state.confirmed = snapshot.desired
                    state.confirmedToken = token
                    state.confirmedAt = now
                    // A new token arrived meanwhile: the one just registered is now stale.
                    if state.token != token, !state.staleTokens.contains(token) {
                        state.staleTokens.append(token)
                    }
                    await update(state)
                }
            case .disabled:
                if let token = snapshot.confirmedToken ?? snapshot.token, snapshot.rejection == nil, snapshot.isPending {
                    try await api.delete(RegistrationToken(token: token))
                    var state = await current()
                    state.confirmed = .disabled
                    state.confirmedToken = nil
                    await update(state)
                }
            }
            for token in snapshot.staleTokens {
                try await api.delete(RegistrationToken(token: token))
                var state = await current()
                state.staleTokens.removeAll { $0 == token }
                await update(state)
            }
            failures = 0
            retryNotBefore = nil
        } catch {
            await handle(error, sent: snapshot, now: now)
        }
    }

    private func handle(_ failure: AlertAPIFailure, sent snapshot: AlertSyncState, now: Date) async {
        switch failure {
        case .unreachable, .notRegistered:
            retryNotBefore = now.addingTimeInterval(Self.backoff[min(failures, Self.backoff.count - 1)])
            failures += 1
        case .rejected(let error):
            // The rejection belongs to the change that was sent; a newer change gets its own try.
            var state = await current()
            guard state.desired == snapshot.desired, state.token == snapshot.token else { return }
            state.rejection = error
            await update(state)
        case .rateLimited(let retryAfter):
            rateLimitedUntil = now.addingTimeInterval(retryAfter)
            retryNotBefore = rateLimitedUntil
        }
    }

    // MARK: State

    /// The state, loaded from the store once; concurrent first callers share the one load.
    private func current() async -> AlertSyncState {
        if let loaded { return loaded }
        if let loading {
            let state = await loading.value
            return loaded ?? state
        }
        let store = self.store
        let task = Task { await store.load() }
        loading = task
        let state = await task.value
        if loaded == nil { loaded = state }
        loading = nil
        return loaded ?? state
    }

    private func update(_ state: AlertSyncState) async {
        loaded = state
        await store.save(state)
    }
}
