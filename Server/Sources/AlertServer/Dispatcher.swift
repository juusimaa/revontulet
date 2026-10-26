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
    /// trip the circuit breaker.
    static let badTokenLimit = 10
    static let badTokenShare = 0.1
    /// How long an alert stays deliverable after its data time (FR-009).
    static let deliveryWindow: TimeInterval = 20 * 60

    let store: RegistrationStore
    let sender: any PushSender
    let topic: String

    public init(store: RegistrationStore, sender: any PushSender, topic: String) {
        self.store = store
        self.sender = sender
        self.topic = topic
    }

    public func dispatch(_ decisions: [AlertDecision], now: Date) async throws -> DispatchReport {
        var pushes: [(request: PushRequest, registration: Registration)] = []
        for decision in decisions {
            let message = AlertMessage.make(for: decision)
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

        for (request, registration) in pushes {
            var result = await sender.send(request)
            if result == .retryable { result = await sender.send(request) }

            switch result {
            case .delivered:
                report.sent += 1
            case .unregistered(let timestamp):
                // A registration confirmed on or after the day of the answer is a re-registration.
                let day = RegistrationStore.startOfUTCDay(timestamp ?? now)
                if Int(registration.confirmedAt.timeIntervalSince1970) < day { unregistered.append(request.token) }
            case .badDeviceToken:
                badTokens.append(request.token)
                if badTokens.count > badTokenLimit {
                    report.failure = .badDeviceTokens
                    return report
                }
            case .providerTokenRejected:
                report.failure = .providerToken
            case .retryable, .rejected:
                report.dropped += 1
            }
            if report.failure != nil { break }
        }

        for token in unregistered + (report.failure == nil ? badTokens : []) {
            try await store.delete(token: token)
            report.deleted += 1
        }
        return report
    }
}
