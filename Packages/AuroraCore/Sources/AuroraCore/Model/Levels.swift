/// FMI's aurora activity level for a station, from its R value and thresholds.
public enum ActivityLevel: String, Sendable, Hashable, Codable, CaseIterable {
    /// "Revontulet epätodennäköisiä": R below the yellow threshold.
    case unlikely
    /// "Revontulet mahdollisia": R between the yellow and red thresholds.
    case possible
    /// "Revontulet todennäköisiä": R at or above the red threshold.
    case probable
}

/// How dark the sky is, from the sun's elevation.
public enum Darkness: String, Sendable, Hashable, Codable, CaseIterable {
    /// Sun above −6° (day or civil twilight).
    case tooLight
    /// Sun between −12° and −6° (nautical twilight).
    case twilight
    /// Sun at or below −12°.
    case dark
}

/// Cloud cover category used by the chance rules.
public enum CloudCondition: String, Sendable, Hashable, Codable, CaseIterable {
    /// 0–3 octas.
    case clear
    /// 4–6 octas.
    case partly
    /// 7–8 octas.
    case overcast
    /// 9, NaN, or no station within range.
    case unknown
}

/// Cloud cover near a place, with where it was measured.
public struct CloudCover: Sendable, Hashable, Codable {
    public var condition: CloudCondition
    public var octas: Int?
    /// Position of the weather station the value comes from.
    public var source: Coordinate?
    public var distanceKm: Double?

    public init(condition: CloudCondition, octas: Int? = nil, source: Coordinate? = nil, distanceKm: Double? = nil) {
        self.condition = condition
        self.octas = octas
        self.source = source
        self.distanceKm = distanceKm
    }

    public static let unknown = CloudCover(condition: .unknown)
}

/// The headline chance of seeing the aurora, ordered from none to high.
public enum ChanceLevel: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case none
    case low
    case moderate
    case high

    public static func < (lhs: ChanceLevel, rhs: ChanceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What holds the chance down most.
public enum LimitingFactor: String, Sendable, Hashable, Codable, CaseIterable {
    case light
    case twilight
    /// A bright moon lowered the level (chance-rules v2).
    case moon
    case clouds
    case activity
}
