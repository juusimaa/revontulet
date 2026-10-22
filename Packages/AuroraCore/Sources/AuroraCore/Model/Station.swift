/// A magnetometer station used for FMI's aurora activity levels.
public struct Station: Sendable, Hashable, Codable, Identifiable {
    /// FMI station code, e.g. `HAN`.
    public var id: String
    /// Name as published by FMI; not translated.
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// R at or above which aurora is "possible".
    public var yellowThreshold: Double
    /// R at or above which aurora is "probable"; always greater than `yellowThreshold`.
    public var redThreshold: Double

    public init(
        id: String, name: String, latitude: Double, longitude: Double,
        yellowThreshold: Double, redThreshold: Double
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.yellowThreshold = yellowThreshold
        self.redThreshold = redThreshold
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}
