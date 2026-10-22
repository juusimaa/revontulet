import Foundation
import Testing
@testable import AuroraCore

@Suite("Aurora service caching and due times")
struct AuroraServiceCachingTests {
    private let now = utc("2026-10-22T16:35:30Z")
    private let rovaniemi = Place(coordinate: Coordinate(latitude: 66.50, longitude: 25.73),
                                  municipalityCode: "698", source: .currentLocation)
    private let utsjoki = Place(coordinate: Coordinate(latitude: 69.9078, longitude: 27.0265),
                                municipalityCode: "890", source: .manual)
    private static let magnetometer = "fmi::observations::magnetometer::simple"
    private static let weather = "fmi::observations::weather::simple"

    private func onlineClient() throws -> StubHTTPClient {
        StubHTTPClient([
            Self.magnetometer: .data(try MagnetometerFixtures.response(now: now)),
            Self.weather: .fixture(try #require(Fixtures.first(prefix: "clouds-"))),
        ])
    }

    /// Requests made so far, by data type.
    private func counts(_ http: StubHTTPClient) -> (magnetometer: Int, clouds: Int) {
        let urls = http.requestedURLs.map(\.absoluteString)
        return (urls.filter { $0.contains("magnetometer") }.count, urls.filter { $0.contains("weather") }.count)
    }

    private func minutes(_ value: Double) -> TimeInterval { value * 60 }

    @Test func cachedResultIsNilWithEmptyCache() async throws {
        let http = try onlineClient()
        let service = try AuroraService(http: http, cache: InMemoryResultCache())

        #expect(await service.cachedResult() == nil)
        #expect(http.requestedURLs.isEmpty)
    }

    @Test func cachedResultMakesNoNetworkCalls() async throws {
        let cache = InMemoryResultCache()
        let stored = try await AuroraService(http: try onlineClient(), cache: cache)
            .refresh(for: rovaniemi, at: now, force: false)

        // A new launch: fresh service, same cache.
        let http = try onlineClient()
        let service = try AuroraService(http: http, cache: cache)

        #expect(await service.cachedResult() == stored)
        #expect(http.requestedURLs.isEmpty)
    }

    @Test func refreshSavesTheResult() async throws {
        let cache = InMemoryResultCache()
        let service = try AuroraService(http: try onlineClient(), cache: cache)

        let result = try await service.refresh(for: rovaniemi, at: now, force: false)

        #expect(await cache.load() == result)
        #expect(await service.cachedResult() == result)
    }

    @Test func dataIsFetchedOnlyWhenDue() async throws {
        let http = try onlineClient()
        let service = try AuroraService(http: http, cache: InMemoryResultCache())

        _ = try await service.refresh(for: rovaniemi, at: now, force: false)
        #expect(counts(http) == (1, 1))

        // Nothing is due yet; the result is still computed, from the last responses.
        let early = try await service.refresh(for: utsjoki, at: now + minutes(4), force: false)
        #expect(counts(http) == (1, 1))
        #expect(early.place == utsjoki)
        #expect(early.computedAt == now + minutes(4))

        // Magnetometer every 5 minutes, clouds every 10.
        _ = try await service.refresh(for: rovaniemi, at: now + minutes(5), force: false)
        #expect(counts(http) == (2, 1))
        _ = try await service.refresh(for: rovaniemi, at: now + minutes(9), force: false)
        #expect(counts(http) == (2, 1))
        _ = try await service.refresh(for: rovaniemi, at: now + minutes(10), force: false)
        #expect(counts(http) == (3, 2))

        // `force` fetches both regardless.
        _ = try await service.refresh(for: rovaniemi, at: now + minutes(10) + 1, force: true)
        #expect(counts(http) == (4, 3))
    }

    @Test func failedRefreshKeepsTheCachedResultAndReportsOffline() async throws {
        let http = try onlineClient()
        let cache = InMemoryResultCache()
        let service = try AuroraService(http: http, cache: cache)
        let stored = try await service.refresh(for: rovaniemi, at: now, force: false)

        http.set(Self.magnetometer, .failure)
        http.set(Self.weather, .failure)
        await #expect(throws: AuroraServiceError.offline) {
            try await service.refresh(for: rovaniemi, at: now + minutes(6), force: false)
        }

        #expect(await cache.load() == stored)
        #expect(await service.cachedResult() == stored)
    }

    @Test func failedFetchIsRetriedOnTheNextRefresh() async throws {
        let http = try onlineClient()
        let service = try AuroraService(http: http, cache: InMemoryResultCache())
        _ = try await service.refresh(for: rovaniemi, at: now, force: false)

        http.set(Self.magnetometer, .failure)
        _ = try? await service.refresh(for: rovaniemi, at: now + minutes(5), force: false)
        http.set(Self.magnetometer, .data(try MagnetometerFixtures.response(now: now)))
        _ = try await service.refresh(for: rovaniemi, at: now + minutes(6), force: false)

        #expect(counts(http).magnetometer == 3)
    }

    @Test func firstLaunchOfflineThrowsOffline() async throws {
        let http = StubHTTPClient([Self.magnetometer: .failure, Self.weather: .failure])
        let service = try AuroraService(http: http, cache: InMemoryResultCache())

        await #expect(throws: AuroraServiceError.offline) {
            try await service.refresh(for: rovaniemi, at: now, force: false)
        }
    }

    @Test func outdatedAfterThirtyMinutes() async throws {
        let result = try await AuroraService(http: try onlineClient(), cache: InMemoryResultCache())
            .refresh(for: rovaniemi, at: now, force: false)
        let measuredAt = result.reading.measuredAt

        #expect(!result.isOutdated(now: measuredAt))
        #expect(!result.isOutdated(now: measuredAt + minutes(30)))
        #expect(result.isOutdated(now: measuredAt + minutes(30) + 1))
    }
}
