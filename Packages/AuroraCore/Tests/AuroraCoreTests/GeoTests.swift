import Testing
@testable import AuroraCore

@Suite("Geometry")
struct GeoTests {
    private let square = Polygon(outer: [
        Coordinate(latitude: 60, longitude: 24),
        Coordinate(latitude: 60, longitude: 25),
        Coordinate(latitude: 61, longitude: 25),
        Coordinate(latitude: 61, longitude: 24),
    ])

    @Test func haversineHelsinkiToRovaniemi() {
        let helsinki = Coordinate(latitude: 60.1699, longitude: 24.9384)
        let rovaniemi = Coordinate(latitude: 66.5039, longitude: 25.7294)

        let distance = Geo.distanceKm(helsinki, rovaniemi)

        #expect(abs(distance - 705) < 3)
        #expect(Geo.distanceKm(rovaniemi, helsinki) == distance)
        #expect(Geo.distanceKm(helsinki, helsinki) == 0)
    }

    @Test func pointInSquare() {
        #expect(Geo.contains(square, Coordinate(latitude: 60.5, longitude: 24.5)))
        #expect(!Geo.contains(square, Coordinate(latitude: 61.5, longitude: 24.5)))
        #expect(!Geo.contains(square, Coordinate(latitude: 60.5, longitude: 23.9)))
    }

    @Test func pointInConcavePolygon() {
        // A "U" shape: the notch between the arms is outside.
        let u = Polygon(outer: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 3),
            Coordinate(latitude: 3, longitude: 3),
            Coordinate(latitude: 3, longitude: 2),
            Coordinate(latitude: 1, longitude: 2),
            Coordinate(latitude: 1, longitude: 1),
            Coordinate(latitude: 3, longitude: 1),
            Coordinate(latitude: 3, longitude: 0),
        ])

        #expect(Geo.contains(u, Coordinate(latitude: 2, longitude: 0.5)))
        #expect(Geo.contains(u, Coordinate(latitude: 0.5, longitude: 1.5)))
        #expect(!Geo.contains(u, Coordinate(latitude: 2, longitude: 1.5)))
    }

    @Test func pointInHoleIsOutside() {
        let withHole = Polygon(
            outer: square.outer,
            holes: [[
                Coordinate(latitude: 60.4, longitude: 24.4),
                Coordinate(latitude: 60.4, longitude: 24.6),
                Coordinate(latitude: 60.6, longitude: 24.6),
                Coordinate(latitude: 60.6, longitude: 24.4),
            ]]
        )

        #expect(!Geo.contains(withHole, Coordinate(latitude: 60.5, longitude: 24.5)))
        #expect(Geo.contains(withHole, Coordinate(latitude: 60.2, longitude: 24.2)))
    }

    @Test func multiPartPolygons() {
        let island = Polygon(outer: [
            Coordinate(latitude: 62, longitude: 24),
            Coordinate(latitude: 62, longitude: 25),
            Coordinate(latitude: 63, longitude: 25),
        ])

        #expect(Geo.contains([square, island], Coordinate(latitude: 62.2, longitude: 24.8)))
        #expect(Geo.contains([square, island], Coordinate(latitude: 60.5, longitude: 24.5)))
        #expect(!Geo.contains([square, island], Coordinate(latitude: 61.5, longitude: 24.5)))
    }

    @Test func distanceToBoundary() {
        // 0.1° of latitude north of the square's top edge ≈ 11.1 km.
        let north = Coordinate(latitude: 61.1, longitude: 24.5)
        #expect(abs(Geo.distanceToBoundaryKm(north, square) - 11.12) < 0.1)

        // Inside points measure to the nearest edge too.
        let inside = Coordinate(latitude: 60.95, longitude: 24.5)
        #expect(abs(Geo.distanceToBoundaryKm(inside, square) - 5.56) < 0.1)
    }

    @Test func boundingBox() {
        let box = BoundingBox(minLatitude: 60, minLongitude: 24, maxLatitude: 61, maxLongitude: 25)

        #expect(box.contains(Coordinate(latitude: 60.5, longitude: 24.5)))
        #expect(!box.contains(Coordinate(latitude: 59.9, longitude: 24.5)))
    }
}
