import AuroraCore
import Foundation

/// The outcome of dispatching one cycle's decisions.
public struct DispatchReport: Sendable, Equatable {
    public var sent: Int
    public var deleted: Int
    /// Not delivered after one retry; not replayed (FR-009).
    public var dropped: Int
    /// A configuration error that stopped the cycle; reported to the heartbeat.
    public var failure: DispatchFailure?

    public init(sent: Int = 0, deleted: Int = 0, dropped: Int = 0, failure: DispatchFailure? = nil) {
        self.sent = sent
        self.deleted = deleted
        self.dropped = dropped
        self.failure = failure
    }
}

public enum DispatchFailure: Sendable, Equatable {
    /// Too many BadDeviceToken / DeviceTokenNotForTopic answers: almost certainly the instance's
    /// APNs environment or topic does not match the builds registering with it.
    case badDeviceTokens
    /// APNs rejected the provider token (key, key ID or team ID).
    case providerToken
}

/// Turns decisions into pushes to the zone's registrations and handles APNs's answers
/// (contracts/push-notification.md).
public struct Dispatcher: Sendable {
    /// More bad-token answers than this, or than 10 % of the cycle's recipients if that is more,
    /// with nothing delivered, trip the circuit breaker.
    static let badTokenLimit = 10
    static let badTokenShare = 0.1
    /// How long an alert stays deliverable after its data time (FR-009).
    static let deliveryWindow: TimeInterval = 20 * 60
    /// Sends in flight at once; one at a time, 50,000 recipients would take most of an hour.
    static let maxConcurrentSends = 20

    typealias Push = (request: PushRequest, registration: Registration)

    let store: RegistrationStore
    let sender: any PushSender
    /// Send the bright-moon texts (`ALERT_MOON_KEYS`); otherwise the moon case gets the twilight text.
    let moonKeys: Bool

    public init(store: RegistrationStore, sender: any PushSender, moonKeys: Bool = false) {
        self.store = store
        self.sender = sender
        self.moonKeys = moonKeys
    }

    public func dispatch(_ decisions: [AlertDecision], now: Date) async throws -> DispatchReport {
        var pushes: [Push] = []
        for decision in decisions {
            let message = AlertMessage.make(for: decision, moonKeys: moonKeys)
            let collapseID = "\(decision.zoneID)-\(decision.level.name)-\(ZoneAlertState.nightKey(for: now))"
            let expiration = decision.condition.dataTime.addingTimeInterval(Self.deliveryWindow)
            for registration in try await store.registrations(inZone: decision.zoneID)
            where AlertPolicy.admits(registration.threshold, decision.level) {
                pushes.append((PushRequest(token: registration.token, message: message, expiration: expiration, collapseID: collapseID),
                               registration))
            }
        }

        let badTokenLimit = max(Self.badTokenLimit, Int(Double(pushes.count) * Self.badTokenShare))
        var report = DispatchReport()
        var unregistered: [String] = []
        var badTokens: [String] = []

        func record(_ result: PushResult, for push: Push) {
            switch result {
            case .delivered:
                report.sent += 1
            case .unregistered(let timestamp):
                // A registration confirmed on or after the day of the answer is a re-registration.
                let day = RegistrationStore.startOfUTCDay(timestamp ?? now)
                if Int(push.registration.confirmedAt.timeIntervalSince1970) < day { unregistered.append(push.request.token) }
            case .badDeviceToken:
                badTokens.append(push.request.token)
            case .providerTokenRejected:
                // Every other request would be rejected the same way.
                report.failure = .providerToken
            case .retryable, .rejected:
                report.dropped += 1
            }
        }

        // Every recipient is tried, even after many bad tokens: anyone can register a made-up
        // token, so stopping early would let a few fake registrations block everyone's alerts.
        // The first send goes alone, so a rejected provider token stops before any other is sent;
        // the rest run `maxConcurrentSends` at a time, so a big alert reaches everyone in time.
        var pending = pushes[...]
        let sender = self.sender
        if let first = pending.popFirst() {
            record(await Self.send(first.request, with: sender), for: first)
        }
        await withTaskGroup(of: (push: Push, result: PushResult).self) { group in
            var running = 0
            while true {
                while report.failure == nil, running < Self.maxConcurrentSends, let push = pending.popFirst() {
                    group.addTask { (push, await Self.send(push.request, with: sender)) }
                    running += 1
                }
                guard let done = await group.next() else { break }
                running -= 1
                record(done.result, for: done.push)
            }
        }

        // Many bad tokens and nothing delivered: almost certainly the instance's APNs environment
        // or topic is wrong, so the registrations are kept. Next to delivered alerts, bad tokens
        // are bad registrations and are deleted.
        if report.failure == nil, report.sent == 0, badTokens.count > badTokenLimit {
            report.failure = .badDeviceTokens
        }

        for token in unregistered + (report.failure == nil ? badTokens : []) {
            try await store.delete(token: token)
            report.deleted += 1
        }
        return report
    }

    /// One send, retried once when APNs asks for it.
    private static func send(_ request: PushRequest, with sender: any PushSender) async -> PushResult {
        let result = await sender.send(request)
        return result == .retryable ? await sender.send(request) : result
    }
}
