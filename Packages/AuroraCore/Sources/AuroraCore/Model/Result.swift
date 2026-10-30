import Foundation

/// The chance of seeing the aurora, produced only by `ChanceCalculator`.
public struct Chance: Sendable, Hashable, Codable {
    public var level: ChanceLevel
    /// nil only when the level is High with nothing limiting it.
    public var limitingFactor: LimitingFactor?
    /// false when cloud cover is unknown and therefore not part of the chance.
    public var cloudsIncluded: Bool

    public init(level: ChanceLevel, limitingFactor: LimitingFactor?, cloudsIncluded: Bool) {
        self.level = level
        self.limitingFactor = limitingFactor
        self.cloudsIncluded = cloudsIncluded
    }
}

/// A station's R value at a time, and the activity level it gives.
public struct StationReading: Sendable, Hashable, Codable {
    public var station: Station
    /// nil when the 10-minute window has too many missing samples.
    public var r: Double?
    /// End of the R window.
    public var measuredAt: Date
    public var activity: ActivityLevel?

    public init(station: Station, r: Double?, measuredAt: Date, activity: ActivityLevel?) {
        self.station = station
        self.r = r
        self.measuredAt = measuredAt
        self.activity = activity
    }
}

/// Where the user wants to know the chance for.
public enum PlaceSource: String, Sendable, Hashable, Codable {
    case currentLocation
    case manual
}

/// A position in Finland with its municipality. Never leaves the device.
public struct Place: Sendable, Hashable, Codable {
    /// Device position, or the municipality's representative point for manual places.
    public var coordinate: Coordinate
    public var municipalityCode: String
    public var source: PlaceSource

    public init(coordinate: Coordinate, municipalityCode: String, source: PlaceSource) {
        self.coordinate = coordinate
        self.municipalityCode = municipalityCode
        self.source = source
    }
}

/// Everything the main screen shows; cached on the device between launches.
public struct AuroraResult: Sendable, Hashable, Codable {
    public var place: Place
    public var chance: Chance
    public var reading: StationReading
    public var distanceToStationKm: Double
    /// true when the nearest station had no valid R and a more distant one was used.
    public var usedMoreDistantStation: Bool
    public var darkness: Darkness
    public var clouds: CloudCover
    /// The moon at the place; a result cached without it (2.0) does not decode.
    public var moon: MoonState
    public var computedAt: Date

    public init(
        place: Place, chance: Chance, reading: StationReading, distanceToStationKm: Double,
        usedMoreDistantStation: Bool, darkness: Darkness, clouds: CloudCover, moon: MoonState, computedAt: Date
    ) {
        self.place = place
        self.chance = chance
        self.reading = reading
        self.distanceToStationKm = distanceToStationKm
        self.usedMoreDistantStation = usedMoreDistantStation
        self.darkness = darkness
        self.clouds = clouds
        self.moon = moon
        self.computedAt = computedAt
    }
}

extension AuroraResult {
    /// A measurement older than this is marked outdated (FR-006).
    public static let outdatedAfter: TimeInterval = 30 * 60

    /// true when the measurement is more than 30 minutes old at `now`.
    public func isOutdated(now: Date) -> Bool {
        now.timeIntervalSince(reading.measuredAt) > Self.outdatedAfter
    }
}
