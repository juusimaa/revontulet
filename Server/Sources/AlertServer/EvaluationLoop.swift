import AuroraCore
import Foundation
import Logging
import ServiceLifecycle

/// Where the loop gets each cycle's zone conditions; `ZoneEvaluator` in production.
public protocol ZoneConditionSource: Sendable {
    func evaluate(at date: Date) async throws -> [ZoneCondition]
}

extension ZoneEvaluator: ZoneConditionSource {}

/// The external heartbeat (research R9): pinged after every successful cycle, and on
/// configuration errors with failure.
public protocol Heartbeat: Sendable {
    func ping(success: Bool) async
}

/// Every 5 minutes: evaluate all zones, apply the alert rules with the persisted per-zone state,
/// send the alerts, save the state (contracts/alert-rules.md). Only the current cycle's decisions
/// are sent; nothing is replayed after downtime.
public actor EvaluationLoop: Service {
    public enum Outcome: Sendable, Equatable {
        case success(alerts: Int)
        /// Magnetometer data could not be fetched; the heartbeat's grace period covers it.
        case fmiUnavailable
        /// A configuration error stopped sending; the state is not saved so the alerts are
        /// tried again next cycle while the data is fresh.
        case dispatchFailed
        /// Reading or writing the database failed.
        case storageFailed
    }

    static let interval: Duration = .seconds(300)

    private let source: any ZoneConditionSource
    private let store: RegistrationStore
    private let dispatcher: Dispatcher
    private let health: HealthStatus
    private let heartbeat: any Heartbeat
    private let logger: Logger
    private var states: [AlertZone.ID: ZoneAlertState]?

    public init(source: any ZoneConditionSource, store: RegistrationStore, dispatcher: Dispatcher,
                health: HealthStatus, heartbeat: any Heartbeat, logger: Logger = makeLogger()) {
        self.source = source
        self.store = store
        self.dispatcher = dispatcher
        self.health = health
        self.heartbeat = heartbeat
        self.logger = logger
    }

    public func run() async throws {
        while !Task.isCancelled && !Task.isShuttingDownGracefully {
            let started = ContinuousClock.now
            _ = await runCycle(now: Date())
            try? await cancelWhenGracefulShutdown {
                try await Task.sleep(until: started + Self.interval)
            }
        }
    }

    /// One evaluation cycle at `now`.
    public func runCycle(now: Date) async -> Outcome {
        let conditions: [ZoneCondition]
        do {
            conditions = try await source.evaluate(at: now)
        } catch {
            logger.warning("FMI magnetometer data unavailable; no alerts this cycle")
            return .fmiUnavailable
        }

        do {
            var states = try await currentStates()
            var decisions: [AlertDecision] = []
            for condition in conditions {
                let state = states[condition.zoneID] ?? ZoneAlertState(zoneID: condition.zoneID)
                let (decision, next) = AlertPolicy.decide(condition: condition, state: state, now: now)
                states[condition.zoneID] = next
                if let decision { decisions.append(decision) }
            }

            let report = try await dispatcher.dispatch(decisions, now: now)
            if let failure = report.failure {
                logger.error("Sending stopped by a configuration error", metadata: ["failure": "\(failure)"])
                await heartbeat.ping(success: false)
                return .dispatchFailed
            }

            for condition in conditions {
                if let state = states[condition.zoneID] { try await store.saveZoneState(state, zone: condition.zoneID) }
            }
            self.states = states
            if !decisions.isEmpty {
                logger.info("Alerts sent", metadata: [
                    "alerts": "\(decisions.map { "\($0.zoneID)-\($0.level.name)" })",
                    "sent": "\(report.sent)", "deleted": "\(report.deleted)", "dropped": "\(report.dropped)",
                ])
            }
            await health.recordSuccess()
            await heartbeat.ping(success: true)
            return .success(alerts: decisions.count)
        } catch {
            logger.error("Database error in evaluation cycle", metadata: ["error": "\(type(of: error))"])
            return .storageFailed
        }
    }

    private func currentStates() async throws -> [AlertZone.ID: ZoneAlertState] {
        if let states { return states }
        let loaded = try await store.zoneStates(as: ZoneAlertState.self)
        states = loaded
        return loaded
    }
}
