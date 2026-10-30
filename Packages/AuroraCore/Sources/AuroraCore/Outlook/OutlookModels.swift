import Foundation

// MARK: Soon (contracts/soon-rules.md)

/// One minute of solar wind observed at L1, from SWPC's propagated product.
public struct SolarWindSample: Sendable, Hashable, Codable {
    /// Minute observed at L1 (UTC).
    public var time: Date
    /// SWPC's modelled arrival time at Earth.
    public var arrival: Date?
    /// nT, GSM.
    public var bz: Double?
    /// km/s.
    public var speed: Double?
    /// cm⁻³; shown in the details, not part of the rule.
    public var density: Double?

    public init(time: Date, arrival: Date?, bz: Double?, speed: Double?, density: Double?) {
        self.time = time
        self.arrival = arrival
        self.bz = bz
        self.speed = speed
        self.density = density
    }
}

/// Whether activity is about to rise. Quiet < Possible < Likely, for hysteresis.
public enum SoonState: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case quiet
    case possible
    case likely
    /// Data missing or too old.
    case unknown

    public static func < (lhs: SoonState, rhs: SoonState) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .unknown: -1
        case .quiet: 0
        case .possible: 1
        case .likely: 2
        }
    }
}

/// The "soon" state with what it is based on.
public struct SoonSignal: Sendable, Hashable, Codable {
    public var state: SoonState
    /// Median dawn–dusk electric field Ey over the window, mV/m; nil when unknown.
    public var driver: Double?
    /// Time remaining until the first strong minute arrives, rounded to 15 minutes (15…60, where
    /// 60 means "about an hour"); nil when quiet or unknown.
    public var arrivalMinutes: Int?
    /// Newest sample with Bz and speed, for the details.
    public var latest: SolarWindSample?
    /// Time of `latest`.
    public var dataTime: Date?
    /// false when it is too light at the place now and at the arrival time (FR-010).
    public var showsOnMainScreen: Bool

    public init(
        state: SoonState, driver: Double? = nil, arrivalMinutes: Int? = nil, latest: SolarWindSample? = nil,
        dataTime: Date? = nil, showsOnMainScreen: Bool = false
    ) {
        self.state = state
        self.driver = driver
        self.arrivalMinutes = arrivalMinutes
        self.latest = latest
        self.dataTime = dataTime
        self.showsOnMainScreen = showsOnMainScreen
    }

    public static let unknown = SoonSignal(state: .unknown)
}

/// An input with the time it was fetched.
public struct Fetched<Value: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    public var value: Value
    public var fetchedAt: Date

    public init(_ value: Value, fetchedAt: Date) {
        self.value = value
        self.fetchedAt = fetchedAt
    }
}

// MARK: Outlook (contracts/outlook-rules.md)

/// How a Kp value was obtained.
public enum KpKind: String, Sendable, Hashable, Codable, CaseIterable {
    case observed
    case estimated
    case predicted
}

/// A 3-hour UTC block of the planetary Kp index, covering `start ..< start + 3 h`.
public struct KpBlock: Sendable, Hashable, Codable {
    public var start: Date
    /// 0…9, in thirds.
    public var kp: Double
    public var kind: KpKind

    public init(start: Date, kp: Double, kind: KpKind) {
        self.start = start
        self.kp = kp
        self.kind = kind
    }

    public var end: Date { start.addingTimeInterval(3 * 3_600) }
}

/// SWPC's Kp forecast, with observed and estimated blocks before the predicted ones.
public struct KpForecast: Sendable, Hashable, Codable {
    /// Sorted by start.
    public var blocks: [KpBlock]
    /// The product has no issue time; the fetch time is shown as "updated".
    public var fetchedAt: Date

    public init(blocks: [KpBlock], fetchedAt: Date) {
        self.blocks = blocks.sorted { $0.start < $1.start }
        self.fetchedAt = fetchedAt
    }
}

/// A geomagnetic storm watch in effect: the G level predicted for some UTC days.
public struct StormWatch: Sendable, Hashable, Codable {
    /// G1…G5.
    public var level: Int
    /// UTC days, `yyyy-MM-dd`.
    public var days: [String]
    public var issuedAt: Date

    public init(level: Int, days: [String], issuedAt: Date) {
        self.level = level
        self.days = days
        self.issuedAt = issuedAt
    }
}

/// FMI's hourly total cloud cover forecast at a zone's representative position.
public struct CloudForecast: Sendable, Hashable, Codable {
    public var zoneID: String
    /// Percent, by UTC hour.
    public var hourly: [Date: Double]
    /// FMI gives no issue time in the simple query; the fetch time is shown.
    public var fetchedAt: Date

    public init(zoneID: String, hourly: [Date: Double], fetchedAt: Date) {
        self.zoneID = zoneID
        self.hourly = hourly
        self.fetchedAt = fetchedAt
    }
}

/// A dark period (sun at or below −6°) and its relevant hours.
public struct Night: Sendable, Hashable, Codable {
    /// nil when the night is too light.
    public var start: Date?
    public var end: Date?
    /// The Dark part (sun at or below −12°) if there is one, otherwise the whole night; for a
    /// night under way only the part from now on.
    public var relevantStart: Date?
    public var relevantEnd: Date?
    public var reachesDark: Bool

    public init(start: Date?, end: Date?, relevantStart: Date?, relevantEnd: Date?, reachesDark: Bool) {
        self.start = start
        self.end = end
        self.relevantStart = relevantStart
        self.relevantEnd = relevantEnd
        self.reachesDark = reachesDark
    }

    public static let tooLight = Night(start: nil, end: nil, relevantStart: nil, relevantEnd: nil, reachesDark: false)
}

public enum NightKind: String, Sendable, Hashable, Codable, CaseIterable {
    case tonight
    case tomorrow
}

public enum OutlookAvailability: String, Sendable, Hashable, Codable, CaseIterable {
    case available
    /// "None – too light", without any forecast.
    case tooLight
    /// No Kp forecast covers the night (FR-020).
    case unavailable
}

/// Why a night's outlook is what it is: the chance reason, or a storm watch when the watch
/// decided the expected activity.
public enum OutlookReason: Sendable, Hashable, Codable {
    case chance(ChanceReason)
    case stormWatch

    /// Localisation key: `reason.<…>` or `outlook.reason.stormWatch`.
    public var key: String {
        switch self {
        case .chance(let reason): reason.key
        case .stormWatch: "outlook.reason.stormWatch"
        }
    }
}

/// One night's outlook (contracts/outlook-rules.md).
public struct NightOutlook: Sendable, Hashable, Codable {
    public var which: NightKind
    public var night: Night
    public var availability: OutlookAvailability
    /// Expected activity; nil when unavailable or too light.
    public var activity: ActivityLevel?
    /// Kp for the night after watches.
    public var maxKp: Double?
    /// Highest G level of the watches covering the night.
    public var watchLevel: Int?
    public var moon: Bool
    public var darkness: Darkness
    public var clouds: CloudCondition
    public var meanCloudPercent: Double?
    /// nil when unavailable.
    public var chance: Chance?
    public var reason: OutlookReason?
    public var kpFetchedAt: Date?
    public var cloudsFetchedAt: Date?

    public init(
        which: NightKind, night: Night, availability: OutlookAvailability, activity: ActivityLevel? = nil,
        maxKp: Double? = nil, watchLevel: Int? = nil, moon: Bool = false, darkness: Darkness = .tooLight,
        clouds: CloudCondition = .unknown, meanCloudPercent: Double? = nil, chance: Chance? = nil,
        reason: OutlookReason? = nil, kpFetchedAt: Date? = nil, cloudsFetchedAt: Date? = nil
    ) {
        self.which = which
        self.night = night
        self.availability = availability
        self.activity = activity
        self.maxKp = maxKp
        self.watchLevel = watchLevel
        self.moon = moon
        self.darkness = darkness
        self.clouds = clouds
        self.meanCloudPercent = meanCloudPercent
        self.chance = chance
        self.reason = reason
        self.kpFetchedAt = kpFetchedAt
        self.cloudsFetchedAt = cloudsFetchedAt
    }
}

/// Tonight and tomorrow night.
public struct Outlook: Sendable, Hashable, Codable {
    public var tonight: NightOutlook
    public var tomorrow: NightOutlook
    public var computedAt: Date

    public init(tonight: NightOutlook, tomorrow: NightOutlook, computedAt: Date) {
        self.tonight = tonight
        self.tomorrow = tomorrow
        self.computedAt = computedAt
    }
}

// MARK: Snapshot

/// Everything the "soon" line and the outlook show, with the raw inputs they were computed from,
/// so that the next launch can recompute them for another time or place without the network.
/// Cached on the device, separately from the headline's result.
public struct OutlookSnapshot: Sendable, Hashable, Codable {
    /// Shown only while it matches the current place.
    public var place: Place
    public var zoneID: String
    public var computedAt: Date
    public var soon: SoonSignal
    /// nil until the place has a zone and a band.
    public var outlook: Outlook?
    /// The last good fetch of each input.
    public var samples: Fetched<[SolarWindSample]>?
    public var forecast: KpForecast?
    public var watches: Fetched<[StormWatch]>?
    public var clouds: Fetched<[CloudForecast]>?

    public init(
        place: Place, zoneID: String, computedAt: Date, soon: SoonSignal = .unknown, outlook: Outlook? = nil,
        samples: Fetched<[SolarWindSample]>? = nil, forecast: KpForecast? = nil,
        watches: Fetched<[StormWatch]>? = nil, clouds: Fetched<[CloudForecast]>? = nil
    ) {
        self.place = place
        self.zoneID = zoneID
        self.computedAt = computedAt
        self.soon = soon
        self.outlook = outlook
        self.samples = samples
        self.forecast = forecast
        self.watches = watches
        self.clouds = clouds
    }
}
