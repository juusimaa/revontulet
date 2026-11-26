import Foundation

/// A zone's current chance to see, computed with the app's own rules at the zone's
/// representative position (data-model.md).
public struct ZoneCondition: Sendable, Hashable, Codable {
    public var zoneID: AlertZone.ID
    public var chance: Chance
    public var reason: ChanceReason
    /// Usually the zone's own station; the next nearest with data during an outage.
    public var activityStationID: Station.ID
    /// When the activity reading was measured; used for the late-data rule (FR-009).
    public var dataTime: Date

    public init(zoneID: AlertZone.ID, chance: Chance, reason: ChanceReason, activityStationID: Station.ID, dataTime: Date) {
        self.zoneID = zoneID
        self.chance = chance
        self.reason = reason
        self.activityStationID = activityStationID
        self.dataTime = dataTime
    }
}

/// Per-zone repeat state kept by the alert service between cycles. Nothing about users.
public struct ZoneAlertState: Sendable, Hashable, Codable {
    public var zoneID: AlertZone.ID
    /// Levels (Moderate, High) alerted and not yet re-armed.
    public var alertedLevels: Set<ChanceLevel>
    /// When the chance first dropped below each alerted level.
    public var belowSince: [ChanceLevel: Date]
    /// Night key of `alertsTonight`; see `nightKey(for:)`.
    public var night: String
    /// Alerts sent for this zone in `night`.
    public var alertsTonight: Int

    public init(zoneID: AlertZone.ID) {
        self.zoneID = zoneID
        alertedLevels = []
        belowSince = [:]
        night = ""
        alertsTonight = 0
    }

    /// The local date (Europe/Helsinki) of the evening a time belongs to: times before 12:00
    /// count as the previous date. Formatted `yyyy-MM-dd`.
    public static func nightKey(for date: Date) -> String {
        Nights.localDate(date.addingTimeInterval(-12 * 3_600))
    }
}

/// One alert to send this cycle.
public struct AlertDecision: Sendable, Hashable {
    public var zoneID: AlertZone.ID
    public var level: ChanceLevel
    public var condition: ZoneCondition

    public init(zoneID: AlertZone.ID, level: ChanceLevel, condition: ZoneCondition) {
        self.zoneID = zoneID
        self.level = level
        self.condition = condition
    }
}

extension ChanceLevel {
    /// `none`, `low`, `moderate` or `high`; used in collapse ids and logs.
    public var name: String {
        switch self {
        case .none: "none"
        case .low: "low"
        case .moderate: "moderate"
        case .high: "high"
        }
    }
}
