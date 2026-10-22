import Foundation
import Testing
@testable import AuroraCore

@Suite("Aurora service")
struct AuroraServiceTests {
    private let now = utc("2026-10-22T16:35:30Z")
    private let rovaniemi = Place(coordinate: Coordinate(latitude: 66.50, longitude: 25.73),
                                  municipalityCode: "698", source: .currentLocation)
    private static let magnetometer = "fmi::observations::magnetometer::simple"
    private static let weather = "fmi::observations::weather::simple"

    private func service(_ responses: [String: StubHTTPClient.Response]) throws -> (AuroraService, StubHTTPClient) {
        let http = StubHTTPClient(responses)
        return (try AuroraService(http: http), http)
    }

    private func recordedResponses() throws -> [String: StubHTTPClient.Response] {
        [
            Self.magnetometer: .data(try MagnetometerFixtures.response(now: now)),
            Self.weather: .fixture(try #require(Fixtures.first(prefix: "clouds-"))),
        ]
    }

    @Test func completeResultForRovaniemi() async throws {
        let (service, _) = try service(try recordedResponses())

        let result = try await service.refresh(for: rovaniemi, at: now, force: false)

        #expect(result.place == rovaniemi)
        #expect(result.reading.station.id == "RAN")
        #expect(abs(result.distanceToStationKm - 74) < 3)
        #expect(!result.usedMoreDistantStation)
        let r = try #require(result.reading.r)
        #expect(r >= 0)
        #expect(result.reading.activity == ActivityClassifier.level(r: r, station: result.reading.station))
        // The newest recorded sample is 16:35:10; FMI labels R with the end of its last interval.
        #expect(result.reading.measuredAt == utc("2026-10-22T16:35:20Z"))
        #expect(result.darkness == SolarPosition.darkness(latitude: 66.50, longitude: 25.73, at: now))
        #expect(result.clouds.condition != .unknown)
        #expect(result.chance == ChanceCalculator.chance(
            activity: try #require(result.reading.activity), darkness: result.darkness, clouds: result.clouds.condition))
        #expect(result.chance.cloudsIncluded)
        #expect(result.computedAt == now)
    }

    @Test func cloudFailureGivesUnknownClouds() async throws {
        var responses = try recordedResponses()
        responses[Self.weather] = .failure
        let (service, _) = try service(responses)

        let result = try await service.refresh(for: rovaniemi, at: now, force: false)

        #expect(result.clouds == .unknown)
        #expect(!result.chance.cloudsIncluded)
    }

    @Test func magnetometerFailureThrows() async throws {
        var responses = try recordedResponses()
        responses[Self.magnetometer] = .failure
        let (service, _) = try service(responses)

        await #expect(throws: (any Error).self) {
            try await service.refresh(for: rovaniemi, at: now, force: false)
        }
    }

    @Test func noValidStationThrowsNoData() async throws {
        var responses = try recordedResponses()
        // A valid response without any samples, e.g. during a data outage.
        responses[Self.magnetometer] = .data(Data(#"<wfs:FeatureCollection xmlns:wfs="x"></wfs:FeatureCollection>"#.utf8))
        let (service, _) = try service(responses)

        await #expect(throws: AuroraServiceError.noData) {
            try await service.refresh(for: rovaniemi, at: now, force: false)
        }
    }

    @Test func moreDistantStationIsNotedWhenNearestHasNoData() async throws {
        // This fixture has data for Hankasalmi only.
        var responses = try recordedResponses()
        responses[Self.magnetometer] = .fixture("magnetometer-sample.xml")
        let (service, _) = try service(responses)

        let result = try await service.refresh(for: rovaniemi, at: utc("2026-10-22T16:35:47Z"), force: false)

        #expect(result.reading.station.id == "HAN")
        #expect(result.usedMoreDistantStation)
    }

    @Test func requestsContainNoPlaceDerivedValues() async throws {
        let (service, http) = try service(try recordedResponses())
        let utsjoki = Place(coordinate: Coordinate(latitude: 69.9078, longitude: 27.0265),
                            municipalityCode: "890", source: .manual)

        _ = try await service.refresh(for: rovaniemi, at: now, force: true)
        _ = try await service.refresh(for: utsjoki, at: now, force: true)

        let requested = http.requestedURLs
        #expect(requested.count == 4)
        #expect(Set(requested) == [FMIRequests.magnetometer(now: now), FMIRequests.clouds(now: now)])
        for url in requested {
            #expect(!url.absoluteString.contains("66.5"))
            #expect(!url.absoluteString.contains("69.9"))
        }
    }
}
