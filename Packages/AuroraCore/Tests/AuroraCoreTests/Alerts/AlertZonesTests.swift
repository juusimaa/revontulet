import Testing
@testable import AuroraCore

@Suite("Alert zones")
struct AlertZonesTests {
    private let zones = try! AlertZones.all()

    private func zone(_ id: String) -> AlertZone {
        zones.first { $0.id == id }!
    }

    @Test func oneZonePerStation() throws {
        let stations = try ReferenceData.loadStations()

        #expect(zones.count == 10)
        #expect(zones.map(\.id) == stations.map(\.id))
        for zone in zones {
            #expect(zone.id == zone.station.id)
            #expect(zone.representativePosition == zone.station.coordinate)
        }
    }

    @Test(arguments: [
        (Coordinate(latitude: 69.91, longitude: 27.03), "KEV"),  // Utsjoki
        (Coordinate(latitude: 65.01, longitude: 25.47), "OUJ"),  // Oulu
        (Coordinate(latitude: 60.17, longitude: 24.94), "TAR"),  // Helsinki
    ])
    func nearestStation(coordinate: Coordinate, expected: String) {
        #expect(AlertZones.zone(for: coordinate, previous: nil, in: zones).id == expected)
    }

    @Test func atAStationItIsThatStationsZone() {
        for zone in zones {
            #expect(AlertZones.zone(for: zone.station.coordinate, previous: nil, in: zones).id == zone.id)
        }
    }

    @Test func previousZoneKeptWithinHysteresis() {
        // Midway between Pello and Ranua, nudged 2 km towards Ranua: Ranua is nearer, but by
        // less than 5 km, so a previous Pello zone is kept.
        let pello = zone("PEL").station.coordinate, ranua = zone("RAN").station.coordinate
        let point = Self.point(between: pello, ranua, closerToSecondByKm: 2)

        #expect(AlertZones.zone(for: point, previous: nil, in: zones).id == "RAN")
        #expect(AlertZones.zone(for: point, previous: "PEL", in: zones).id == "PEL")
    }

    @Test func previousZoneReplacedWhenAnotherIsFiveKmCloser() {
        let pello = zone("PEL").station.coordinate, ranua = zone("RAN").station.coordinate
        let point = Self.point(between: pello, ranua, closerToSecondByKm: 6)

        #expect(AlertZones.zone(for: point, previous: "PEL", in: zones).id == "RAN")
    }

    @Test func unknownPreviousZoneIsIgnored() {
        let oulu = Coordinate(latitude: 65.01, longitude: 25.47)

        #expect(AlertZones.zone(for: oulu, previous: "XXX", in: zones).id == "OUJ")
    }

    @Test func hysteresisMatchesStationSelector() {
        #expect(AlertZones.hysteresisKm == StationSelector.hysteresisKm)
    }

    /// A point on the line between `a` and `b` whose distance to `b` is `km` less than to `a`.
    private static func point(between a: Coordinate, _ b: Coordinate, closerToSecondByKm km: Double) -> Coordinate {
        // Bisect along the segment for the fraction where d(a) - d(b) == km.
        var low = 0.0, high = 1.0
        for _ in 0..<60 {
            let t = (low + high) / 2
            let p = Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
            if Geo.distanceKm(p, a) - Geo.distanceKm(p, b) < km { low = t } else { high = t }
        }
        return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * low,
                          longitude: a.longitude + (b.longitude - a.longitude) * low)
    }
}
