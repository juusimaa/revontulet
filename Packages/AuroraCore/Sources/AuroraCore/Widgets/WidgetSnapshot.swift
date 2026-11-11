import Foundation

/// What a widget shows, derived from a cached result and outlook so that the view does no logic.
public struct WidgetSnapshot: Sendable, Hashable {
    public var level: ChanceLevel
    public var reason: ChanceReason
    public var cloudsIncluded: Bool
    public var municipalityCode: String
    public var stationName: String
    public var rValue: Double?
    public var measuredAt: Date
    /// FMI's activity wording for the reading; the Soon line words itself differently when it is probable.
    public var activity: ActivityLevel?
    public var isStale: Bool
    public var soon: SoonSignal?
    public var tonight: NightOutlook?

    public init(
        level: ChanceLevel, reason: ChanceReason, cloudsIncluded: Bool, municipalityCode: String,
        stationName: String, rValue: Double?, measuredAt: Date, activity: ActivityLevel? = nil, isStale: Bool,
        soon: SoonSignal? = nil, tonight: NightOutlook? = nil
    ) {
        self.level = level
        self.reason = reason
        self.cloudsIncluded = cloudsIncluded
        self.municipalityCode = municipalityCode
        self.stationName = stationName
        self.rValue = rValue
        self.measuredAt = measuredAt
        self.activity = activity
        self.isStale = isStale
        self.soon = soon
        self.tonight = tonight
    }

    /// The outlook is used only when it belongs to the result's municipality.
    public static func make(result: AuroraResult, outlook: OutlookSnapshot?, now: Date) -> WidgetSnapshot {
        let code = result.place.municipalityCode
        let matching = outlook.flatMap { $0.place.municipalityCode == code ? $0 : nil }
        let tonight = matching?.outlook.flatMap { $0.tonight.which == .tonight ? $0.tonight : nil }
        return WidgetSnapshot(
            level: result.chance.level, reason: result.reason, cloudsIncluded: result.chance.cloudsIncluded,
            municipalityCode: code, stationName: result.reading.station.name, rValue: result.reading.r,
            measuredAt: result.reading.measuredAt, activity: result.reading.activity, isStale: result.isOutdated(now: now),
            soon: matching?.soon, tonight: tonight)
    }
}
