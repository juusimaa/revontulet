/// A coarse area of Finland: where one magnetometer station is the nearest of the bundled ones.
/// Identified by the station code; alerts and settings name it after the station.
public struct AlertZone: Sendable, Hashable, Codable, Identifiable {
    /// The station code, e.g. `OUJ`.
    public var id: String
    public var station: Station

    public init(station: Station) {
        self.id = station.id
        self.station = station
    }

    /// Where darkness and cloud cover are evaluated for the zone (research R2).
    public var representativePosition: Coordinate { station.coordinate }
}

/// The alert zones and how a place maps to one.
public enum AlertZones {
    /// A previous zone is kept unless another station is at least this much closer; the same
    /// hysteresis as station selection, so registrations do not flip at a zone border.
    static let hysteresisKm = StationSelector.hysteresisKm

    /// All zones, one per bundled station, in the bundled order.
    public static func all() throws -> [AlertZone] {
        try ReferenceData.loadStations().map(AlertZone.init(station:))
    }

    /// The zone of the nearest station to `coordinate`, regardless of whether it has data, so the
    /// zone depends only on geography. Keeps `previous` unless another station is at least 5 km
    /// closer. `zones` must not be empty.
    public static func zone(for coordinate: Coordinate, previous: AlertZone.ID?, in zones: [AlertZone]) -> AlertZone {
        let ranked = zones
            .map { (zone: $0, distance: Geo.distanceKm(coordinate, $0.representativePosition)) }
            .sorted { $0.distance < $1.distance }
        let nearest = ranked[0]
        if let previous, let kept = ranked.first(where: { $0.zone.id == previous }),
           kept.distance - nearest.distance < hysteresisKm {
            return kept.zone
        }
        return nearest.zone
    }
}
