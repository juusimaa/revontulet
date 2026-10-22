import Foundation

public enum AuroraServiceError: Error, Equatable, Sendable {
    /// No station has a valid R value, so no chance can be calculated.
    case noData
}

/// Fetches FMI data and turns it into the result for a place (contracts/aurora-core-api.md).
public actor AuroraService {
    private let client: FMIClient
    private let stations: [Station]
    /// Station used for the last result, for hysteresis in station selection.
    private var previousStationID: Station.ID?

    public init(http: any HTTPClient) throws {
        self.init(http: http, stations: try ReferenceData.loadStations())
    }

    init(http: any HTTPClient, stations: [Station]) {
        client = FMIClient(http: http, stations: stations)
        self.stations = stations
    }

    /// Fetches magnetometer and cloud data and computes the result for `place` at `date`.
    ///
    /// A cloud fetch failure gives unknown clouds; a magnetometer failure throws, and so does a
    /// response in which no station has a valid R (`AuroraServiceError.noData`).
    public func refresh(for place: Place, at date: Date, force: Bool) async throws -> AuroraResult {
        async let cloudsFetch = client.cloudObservations(now: date)
        let samples = try await client.magnetometerSamples(now: date)
        let observations = (try? await cloudsFetch) ?? []

        let readings = Self.readings(stations: stations, samples: samples, now: date)
        guard let selection = StationSelector.select(for: place, readings: readings, previous: previousStationID),
              let activity = selection.reading.activity
        else { throw AuroraServiceError.noData }
        previousStationID = selection.reading.station.id

        let darkness = SolarPosition.darkness(
            latitude: place.coordinate.latitude, longitude: place.coordinate.longitude, at: date)
        let clouds = CloudSelector.select(for: place.coordinate, observations: observations)
        return AuroraResult(
            place: place,
            chance: ChanceCalculator.chance(activity: activity, darkness: darkness, clouds: clouds.condition),
            reading: selection.reading,
            distanceToStationKm: selection.distanceKm,
            usedMoreDistantStation: selection.usedMoreDistantStation,
            darkness: darkness,
            clouds: clouds,
            computedAt: date)
    }

    /// One reading per station. R ends at each station's latest complete sample; stations without
    /// usable data get a nil R.
    static func readings(stations: [Station], samples: [MagnetometerSample], now: Date) -> [StationReading] {
        let byStation = Dictionary(grouping: samples, by: \.stationID)
        return stations.map { station in
            let stationSamples = byStation[station.id] ?? []
            let latest = stationSamples.filter { $0.x != nil && $0.y != nil && $0.z != nil }.map(\.time).max()
            guard let latest else {
                return StationReading(station: station, r: nil, measuredAt: now, activity: nil)
            }
            // FMI labels R with the end of the last 10 s interval.
            let end = latest.addingTimeInterval(TimeInterval(RIndex.sampleInterval))
            let r = RIndex.compute(samples: stationSamples, end: end)
            return StationReading(
                station: station, r: r, measuredAt: end,
                activity: r.map { ActivityClassifier.level(r: $0, station: station) })
        }
    }
}

extension AuroraResult {
    /// The reason shown with the chance level.
    public var reason: ChanceReason {
        ChanceCalculator.reason(for: chance, activity: reading.activity ?? .unlikely, clouds: clouds.condition)
    }
}
