import Foundation

/// Computes every zone's chance with exactly the app's rules (contracts/alert-rules.md §1).
///
/// Fetches what is due, as `AuroraService` does: magnetometer data at most every 5 minutes and
/// cloud cover at most every 10 minutes, all of Finland in one request each, for all users
/// together. Adds no calculation of its own, so an alert and the app's result always agree.
public actor ZoneEvaluator {
    private let client: FMIClient
    private let stations: [Station]
    private var magnetometer: (fetchedAt: Date, samples: [MagnetometerSample])?
    private var clouds: (fetchedAt: Date, observations: [CloudObservation])?

    public init(http: any HTTPClient) throws {
        self.init(http: http, stations: try ReferenceData.loadStations())
    }

    init(http: any HTTPClient, stations: [Station]) {
        client = FMIClient(http: http, stations: stations)
        self.stations = stations
    }

    /// One condition per zone whose activity can be computed. Throws
    /// `AuroraServiceError.offline` when magnetometer data cannot be fetched; a failed cloud
    /// fetch gives unknown clouds and is retried on the next evaluation.
    public func evaluate(at date: Date) async throws -> [ZoneCondition] {
        let magnetometerDue = magnetometer.map { date.timeIntervalSince($0.fetchedAt) >= AuroraService.magnetometerInterval } ?? true
        let cloudsDue = clouds.map { date.timeIntervalSince($0.fetchedAt) >= AuroraService.cloudsInterval } ?? true

        async let cloudsFetch: [CloudObservation]? = cloudsDue ? try? client.cloudObservations(now: date) : nil
        if magnetometerDue {
            do {
                magnetometer = (date, try await client.magnetometerSamples(now: date))
            } catch {
                _ = await cloudsFetch
                throw AuroraServiceError.offline
            }
        }
        if cloudsDue {
            clouds = await cloudsFetch.map { (date, $0) }
        }

        let readings = AuroraService.readings(stations: stations, samples: magnetometer?.samples ?? [], now: date)
        return stations.compactMap { station in
            let place = Place(coordinate: station.coordinate, municipalityCode: "", source: .manual)
            guard let selection = StationSelector.select(for: place, readings: readings, previous: nil),
                  let activity = selection.reading.activity
            else { return nil }
            let darkness = SolarPosition.darkness(latitude: station.latitude, longitude: station.longitude, at: date)
            let cloudCover = CloudSelector.select(for: station.coordinate, observations: clouds?.observations ?? [])
            let chance = ChanceCalculator.chance(activity: activity, darkness: darkness, clouds: cloudCover.condition)
            return ZoneCondition(
                zoneID: station.id,
                chance: chance,
                reason: ChanceCalculator.reason(for: chance, activity: activity, clouds: cloudCover.condition),
                activityStationID: selection.reading.station.id,
                dataTime: selection.reading.measuredAt)
        }
    }
}
