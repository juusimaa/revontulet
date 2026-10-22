/// Picks the cloud cover observation for a place (research.md R5).
public enum CloudSelector {
    static let maxDistanceKm = 100.0

    /// The nearest observation with a valid value within 100 km, or unknown.
    public static func select(for coordinate: Coordinate, observations: [CloudObservation]) -> CloudCover {
        let nearest = observations
            .compactMap { observation in
                observation.octas.map { (observation, octas: $0, distance: Geo.distanceKm(coordinate, observation.coordinate)) }
            }
            .filter { $0.distance <= maxDistanceKm }
            .min { $0.distance < $1.distance }
        guard let nearest else { return .unknown }
        return CloudCover(
            condition: ChanceCalculator.cloudCondition(octas: nearest.octas),
            octas: nearest.octas,
            source: nearest.0.coordinate,
            distanceKm: nearest.distance)
    }
}
