import Foundation

/// Geometry on WGS84 coordinates, accurate enough for distances within Finland.
public enum Geo {
    static let earthRadiusKm = 6371.0
    static let kmPerDegree = earthRadiusKm * .pi / 180

    /// Great-circle (haversine) distance in kilometres.
    public static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Whether the point is inside the polygon's outer ring and not inside any hole.
    public static func contains(_ polygon: Polygon, _ point: Coordinate) -> Bool {
        ringContains(polygon.outer, point) && !polygon.holes.contains { ringContains($0, point) }
    }

    /// Whether the point is inside any of the polygons.
    public static func contains(_ polygons: [Polygon], _ point: Coordinate) -> Bool {
        polygons.contains { contains($0, point) }
    }

    /// Shortest distance in kilometres from the point to the polygon's rings (outer and holes).
    public static func distanceToBoundaryKm(_ point: Coordinate, _ polygon: Polygon) -> Double {
        ([polygon.outer] + polygon.holes).map { ringDistanceKm(point, $0) }.min() ?? .infinity
    }

    /// Shortest distance in kilometres from the point to any of the polygons' rings.
    public static func distanceToBoundaryKm(_ point: Coordinate, _ polygons: [Polygon]) -> Double {
        polygons.map { distanceToBoundaryKm(point, $0) }.min() ?? .infinity
    }

    // Ray casting with longitude as x and latitude as y.
    private static func ringContains(_ ring: [Coordinate], _ point: Coordinate) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let crossLongitude = a.longitude
                    + (point.latitude - a.latitude) / (b.latitude - a.latitude) * (b.longitude - a.longitude)
                if point.longitude < crossLongitude { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    // Distance to the ring's segments in a local equirectangular projection centred on the point.
    private static func ringDistanceKm(_ point: Coordinate, _ ring: [Coordinate]) -> Double {
        guard !ring.isEmpty else { return .infinity }
        let kx = cos(point.latitude * .pi / 180) * kmPerDegree
        func project(_ c: Coordinate) -> (x: Double, y: Double) {
            ((c.longitude - point.longitude) * kx, (c.latitude - point.latitude) * kmPerDegree)
        }
        var best = Double.infinity
        var previous = project(ring[ring.count - 1])
        for coordinate in ring {
            let current = project(coordinate)
            best = min(best, segmentDistanceToOrigin(previous, current))
            previous = current
        }
        return best
    }

    private static func segmentDistanceToOrigin(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, -(a.x * dx + a.y * dy) / lengthSquared))
        let x = a.x + t * dx, y = a.y + t * dy
        return (x * x + y * y).squareRoot()
    }
}
