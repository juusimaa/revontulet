import Foundation

public enum AuroraServiceError: Error, Equatable, Sendable {
    /// No station has a valid R value, so no chance can be calculated.
    case noData
    /// Magnetometer data could not be fetched (no connection, server error or bad response).
    case offline
}

/// Fetches FMI data and turns it into the result for a place (contracts/aurora-core-api.md).
///
/// Magnetometer data is fetched at most every 5 minutes and cloud cover at most every 10 minutes
/// unless a refresh is forced; in between, results are computed from the last responses.
public actor AuroraService {
    static let magnetometerInterval: TimeInterval = 5 * 60
    static let cloudsInterval: TimeInterval = 10 * 60

    private let client: FMIClient
    private let stations: [Station]
    private let cache: any ResultCache
    /// Station used for the last result, for hysteresis in station selection.
    private var previousStationID: Station.ID?
    private var magnetometer: (fetchedAt: Date, samples: [MagnetometerSample])?
    private var clouds: (fetchedAt: Date, observations: [CloudObservation])?

    public init(http: any HTTPClient, cache: any ResultCache) throws {
        self.init(http: http, cache: cache, stations: try ReferenceData.loadStations())
    }

    init(http: any HTTPClient, cache: any ResultCache, stations: [Station]) {
        client = FMIClient(http: http, stations: stations)
        self.stations = stations
        self.cache = cache
    }

    /// The last stored result, if any. Never touches the network (FR-008).
    public func cachedResult() async -> AuroraResult? {
        let result = await cache.load()
        if previousStationID == nil { previousStationID = result?.reading.station.id }
        return result
    }

    /// Fetches what is due and computes the result for `place` at `date`, then stores it.
    ///
    /// A cloud fetch failure gives unknown clouds. A magnetometer fetch failure throws
    /// `AuroraServiceError.offline`, and a response in which no station has a valid R throws
    /// `AuroraServiceError.noData`; in both cases the stored result is left as it was.
    public func refresh(for place: Place, at date: Date, force: Bool) async throws -> AuroraResult {
        let magnetometerDue = force || magnetometer.map { date.timeIntervalSince($0.fetchedAt) >= Self.magnetometerInterval } ?? true
        let cloudsDue = force || clouds.map { date.timeIntervalSince($0.fetchedAt) >= Self.cloudsInterval } ?? true

        async let cloudsFetch: [CloudObservation]? = cloudsDue ? try? client.cloudObservations(now: date) : nil
        if magnetometerDue {
            do {
                magnetometer = (date, try await client.magnetometerSamples(now: date))
            } catch {
                throw AuroraServiceError.offline
            }
        }
        if cloudsDue {
            // A failed cloud fetch is retried on the next refresh; until then clouds are unknown.
            clouds = await cloudsFetch.map { (date, $0) }
        }

        let readings = Self.readings(stations: stations, samples: magnetometer?.samples ?? [], now: date)
        guard let selection = StationSelector.select(for: place, readings: readings, previous: previousStationID),
              let activity = selection.reading.activity
        else { throw AuroraServiceError.noData }
        previousStationID = selection.reading.station.id

        let darkness = SolarPosition.darkness(
            latitude: place.coordinate.latitude, longitude: place.coordinate.longitude, at: date)
        let cloudCover = CloudSelector.select(for: place.coordinate, observations: clouds?.observations ?? [])
        let result = AuroraResult(
            place: place,
            chance: ChanceCalculator.chance(activity: activity, darkness: darkness, clouds: cloudCover.condition),
            reading: selection.reading,
            distanceToStationKm: selection.distanceKm,
            usedMoreDistantStation: selection.usedMoreDistantStation,
            darkness: darkness,
            clouds: cloudCover,
            computedAt: date)
        await cache.save(result)
        return result
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
