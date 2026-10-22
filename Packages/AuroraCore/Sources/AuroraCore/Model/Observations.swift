import Foundation

/// One 10-second magnetometer average for a station. Values are nT; nil when FMI reports NaN.
public struct MagnetometerSample: Sendable, Hashable, Codable {
    public var stationID: String
    public var time: Date
    public var x: Double?
    public var y: Double?
    public var z: Double?

    public init(stationID: String, time: Date, x: Double?, y: Double?, z: Double?) {
        self.stationID = stationID
        self.time = time
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Total cloud cover reported by a weather station.
public struct CloudObservation: Sendable, Hashable, Codable {
    public var coordinate: Coordinate
    public var time: Date
    /// Octas 0–8; nil for 9 (sky obscured) or NaN.
    public var octas: Int?

    public init(coordinate: Coordinate, time: Date, octas: Int?) {
        self.coordinate = coordinate
        self.time = time
        self.octas = octas
    }
}
