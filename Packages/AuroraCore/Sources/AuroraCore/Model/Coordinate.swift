/// A WGS84 position in degrees.
public struct Coordinate: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// An axis-aligned latitude/longitude box, used to skip polygons quickly.
public struct BoundingBox: Sendable, Hashable, Codable {
    public var minLatitude: Double
    public var minLongitude: Double
    public var maxLatitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.minLongitude = minLongitude
        self.maxLatitude = maxLatitude
        self.maxLongitude = maxLongitude
    }

    public func contains(_ point: Coordinate) -> Bool {
        (minLatitude...maxLatitude).contains(point.latitude)
            && (minLongitude...maxLongitude).contains(point.longitude)
    }
}

/// One part of an area: an outer ring and optional holes. Rings are implicitly closed.
public struct Polygon: Sendable, Hashable, Codable {
    public var outer: [Coordinate]
    public var holes: [[Coordinate]]

    public init(outer: [Coordinate], holes: [[Coordinate]] = []) {
        self.outer = outer
        self.holes = holes
    }
}
