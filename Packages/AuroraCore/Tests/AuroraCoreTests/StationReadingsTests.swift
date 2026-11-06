import Foundation
import Testing
@testable import AuroraCore

/// The readings of every station for the map of Finland (issue #2).
@Suite("Station readings for the map")
struct StationReadingsTests {
    private let now = utc("2026-10-22T16:35:30Z")
    private let rovaniemi = Place(coordinate: Coordinate(latitude: 66.50, longitude: 25.73),
                                  municipalityCode: "698", source: .currentLocation)
    private static let magnetometer = "fmi::observations::magnetometer::simple"
    private static let weather = "fmi::observations::weather::simple"

    private func onlineClient() throws -> StubHTTPClient {
        StubHTTPClient([
            Self.magnetometer: .data(try MagnetometerFixtures.response(now: now)),
            Self.weather: .fixture(try #require(Fixtures.first(prefix: "clouds-"))),
        ])
    }

    @Test func returnsEveryStationClassifiedByItsOwnThresholds() async throws {
        let service = try AuroraService(http: try onlineClient(), cache: InMemoryResultCache())

        let readings = try await service.stationReadings(at: now, force: false)

        #expect(readings.map(\.station.id) == (try ReferenceData.loadStations()).map(\.id))
        for reading in readings {
            if let r = reading.r {
                #expect(reading.activity == ActivityClassifier.level(r: r, station: reading.station))
            } else {
                #expect(reading.activity == nil)
            }
        }
        #expect(readings.contains { $0.r != nil })
    }

    @Test func fetchesOnlyMagnetometerData() async throws {
        let http = try onlineClient()
        let service = try AuroraService(http: http, cache: InMemoryResultCache())

        _ = try await service.stationReadings(at: now, force: false)

        #expect(http.count("magnetometer") == 1)
        #expect(http.count("weather") == 0)
    }

    @Test func sharesTheFetchWithTheHeadline() async throws {
        let http = try onlineClient()
        let service = try AuroraService(http: http, cache: InMemoryResultCache())

        let result = try await service.refresh(for: rovaniemi, at: now, force: false)
        let readings = try await service.stationReadings(at: now.addingTimeInterval(60), force: false)

        #expect(http.count("magnetometer") == 1)
        #expect(readings.first { $0.station.id == result.reading.station.id }?.r == result.reading.r)
    }

    @Test func fetchesAgainWhenDueOrForced() async throws {
        let http = try onlineClient()
        let service = try AuroraService(http: http, cache: InMemoryResultCache())

        _ = try await service.stationReadings(at: now, force: false)
        _ = try await service.stationReadings(at: now.addingTimeInterval(60), force: true)
        _ = try await service.stationReadings(at: now.addingTimeInterval(6 * 60), force: false)

        #expect(http.count("magnetometer") == 3)
    }

    @Test func doesNotTouchTheStoredResult() async throws {
        let cache = InMemoryResultCache()
        let service = try AuroraService(http: try onlineClient(), cache: cache)

        _ = try await service.stationReadings(at: now, force: false)

        #expect(await cache.load() == nil)
    }

    @Test func failedFetchIsOffline() async throws {
        let http = try onlineClient()
        http.set(Self.magnetometer, .failure)
        let service = try AuroraService(http: http, cache: InMemoryResultCache())

        await #expect(throws: AuroraServiceError.offline) {
            try await service.stationReadings(at: now, force: false)
        }
    }
}
