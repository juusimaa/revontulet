/// The station whose reading is used for a place, and how far away it is.
public struct StationSelection: Sendable, Hashable {
    public var reading: StationReading
    public var distanceKm: Double
    /// true when a closer station had no valid R.
    public var usedMoreDistantStation: Bool
}

/// Picks the station for a place (FR-005).
public enum StationSelector {
    /// A previously used station is kept unless another valid station is at least this much closer.
    static let hysteresisKm = 5.0

    /// The nearest station with a valid R, keeping `previous` while it is within the hysteresis
    /// distance so the station does not flip back and forth. nil when no station has a valid R.
    public static func select(for place: Place, readings: [StationReading], previous: Station.ID?) -> StationSelection? {
        let ranked = readings
            .map { (reading: $0, distance: Geo.distanceKm(place.coordinate, $0.station.coordinate)) }
            .sorted { $0.distance < $1.distance }
        let valid = ranked.filter { $0.reading.r != nil }
        guard let nearest = valid.first else { return nil }

        var chosen = nearest
        if let previous, let kept = valid.first(where: { $0.reading.station.id == previous }),
           kept.distance - nearest.distance < hysteresisKm {
            chosen = kept
        }
        let skippedCloser = ranked.contains { $0.reading.r == nil && $0.distance < nearest.distance }
        return StationSelection(reading: chosen.reading, distanceKm: chosen.distance, usedMoreDistantStation: skippedCloser)
    }
}
