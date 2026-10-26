import Foundation

/// When to alert a zone (contracts/alert-rules.md §2). Pure: no clock, no I/O.
public enum AlertPolicy {
    /// Levels that can alert, lowest first.
    static let alertableLevels: [ChanceLevel] = [.moderate, .high]
    /// An alerted level re-arms after the chance has been below it continuously this long.
    static let rearmAfter: TimeInterval = 60 * 60
    /// Data older than this is not alerted on (FR-009).
    static let maxDataAge: TimeInterval = 20 * 60
    /// Alerts per zone per night (SC-003).
    static let nightlyCap = 3

    public static func decide(condition: ZoneCondition, state: ZoneAlertState, now: Date)
        -> (decision: AlertDecision?, state: ZoneAlertState) {
        var state = state
        let level = condition.chance.level

        // 1. Night.
        let night = ZoneAlertState.nightKey(for: now)
        if night != state.night {
            state.night = night
            state.alertsTonight = 0
        }

        // 2. Re-arm.
        for alerted in alertableLevels where state.alertedLevels.contains(alerted) {
            if level < alerted {
                let since = state.belowSince[alerted] ?? now
                state.belowSince[alerted] = since
                if now.timeIntervalSince(since) >= rearmAfter {
                    state.alertedLevels.remove(alerted)
                    state.belowSince[alerted] = nil
                }
            } else {
                state.belowSince[alerted] = nil
            }
        }

        // 3. Candidate: the highest level reached and not alerted.
        guard let candidate = alertableLevels.last(where: { level >= $0 && !state.alertedLevels.contains($0) }) else {
            return (nil, state)
        }

        // 4. Late data: dropped, not marked, so it may alert later with fresh data.
        if now.timeIntervalSince(condition.dataTime) > maxDataAge {
            return (nil, state)
        }

        // 5–6. The candidate and every lower level count as alerted, sent or capped.
        state.alertedLevels.formUnion(alertableLevels.filter { $0 <= candidate })
        if state.alertsTonight >= nightlyCap {
            return (nil, state)
        }
        state.alertsTonight += 1
        return (AlertDecision(zoneID: condition.zoneID, level: candidate, condition: condition), state)
    }

    /// Whether a registration with `threshold` receives an alert for `level`: Moderate alerts go
    /// to `moderate` registrations only; High alerts to both.
    public static func admits(_ threshold: AlertThreshold, _ level: ChanceLevel) -> Bool {
        switch threshold {
        case .moderate: level >= .moderate
        case .high: level >= .high
        }
    }
}
