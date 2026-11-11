import AuroraCore
import Foundation
import Synchronization
import Testing
@testable import Revontulet

/// The widget extension fetches sparingly: shared in-flight fetches, nothing while the cache is fresh,
/// never forced (specs/004-ios-widgets/contracts/widget-refresh.md).
@Suite("Widget data loader")
struct WidgetDataLoaderTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let place = Place(
        coordinate: Coordinate(latitude: 66.5, longitude: 25.7), municipalityCode: "698", source: .manual)

    /// Serves the UI-test stubs and counts requests (magnetometer ones separately).
    final class CountingHTTPClient: HTTPClient {
        private let stubs = UITestHTTPClient()
        private let counts = Mutex<(all: Int, magnetometer: Int)>((0, 0))
        var magnetometerRequests: Int { counts.withLock { $0.magnetometer } }
        var requests: Int { counts.withLock { $0.all } }

        func get(_ url: URL) async throws -> (Data, Int) {
            let isMagnetometer = url.absoluteString.contains("magnetometer")
            counts.withLock { counts in
                counts.all += 1
                if isMagnetometer { counts.magnetometer += 1 }
            }
            return try await stubs.get(url)
        }
    }

    struct OfflineHTTPClient: HTTPClient {
        func get(_ url: URL) async throws -> (Data, Int) { throw URLError(.notConnectedToInternet) }
    }

    private static func cached(ageMin: Double, code: String = "698") -> AuroraResult {
        let measured = now.addingTimeInterval(-ageMin * 60)
        return AuroraResult(
            place: Place(coordinate: place.coordinate, municipalityCode: code, source: .manual),
            chance: Chance(level: .moderate, limitingFactor: nil, cloudsIncluded: true),
            reading: StationReading(
                station: Station(id: "KEV", name: "Kevo", latitude: 69.761, longitude: 27.01,
                    yellowThreshold: 55, redThreshold: 165),
                r: 120, measuredAt: measured, activity: .probable),
            distanceToStationKm: 16.4, usedMoreDistantStation: false, darkness: .dark,
            clouds: CloudCover(condition: .clear),
            moon: MoonState(altitude: -10, illuminatedFraction: 0.2, phase: .waxingCrescent, isBright: false),
            computedAt: measured)
    }

    @Test func concurrentCallsShareOneFetch() async {
        let http = CountingHTTPClient()
        let loader = WidgetDataLoader(
            http: http, resultCache: InMemoryResultCache(Self.cached(ageMin: 30)),
            outlookCache: InMemoryOutlookCache())

        let results = await withTaskGroup(of: AuroraResult?.self) { group in
            for _ in 0..<5 { group.addTask { await loader.result(for: Self.place, at: Self.now) } }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(http.magnetometerRequests == 1)
        #expect(results.count == 5)
        #expect(results.allSatisfy { $0 != nil && $0 == results[0] })
        #expect(results[0] != Self.cached(ageMin: 30))
    }

    @Test func freshCacheMakesNoRequest() async {
        let http = CountingHTTPClient()
        let fresh = Self.cached(ageMin: 4)
        let loader = WidgetDataLoader(
            http: http, resultCache: InMemoryResultCache(fresh), outlookCache: InMemoryOutlookCache())

        let result = await loader.result(for: Self.place, at: Self.now)

        #expect(http.requests == 0)
        #expect(result == fresh)
    }

    @Test func offlineReturnsTheStaleCache() async {
        let stale = Self.cached(ageMin: 30)
        let cache = InMemoryResultCache(stale)
        let loader = WidgetDataLoader(http: OfflineHTTPClient(), resultCache: cache, outlookCache: InMemoryOutlookCache())

        let result = await loader.result(for: Self.place, at: Self.now)

        #expect(result == stale)
        #expect(await cache.load() == stale)
    }

    @Test func secondCallAMinuteLaterDoesNotFetchAgain() async {
        let http = CountingHTTPClient()
        let loader = WidgetDataLoader(
            http: http, resultCache: InMemoryResultCache(), outlookCache: InMemoryOutlookCache())

        let first = await loader.result(for: Self.place, at: Self.now)
        let second = await loader.result(for: Self.place, at: Self.now.addingTimeInterval(60))

        #expect(first != nil)
        #expect(second == first)
        #expect(http.magnetometerRequests == 1)
    }

    @Test func outlookFetchesOnceThenReusesTheSnapshot() async throws {
        let http = CountingHTTPClient()
        let loader = WidgetDataLoader(
            http: http, resultCache: InMemoryResultCache(), outlookCache: InMemoryOutlookCache())

        let first = try #require(await loader.outlook(for: Self.place, at: Self.now))
        let requests = http.requests
        let second = await loader.outlook(for: Self.place, at: Self.now.addingTimeInterval(120))

        #expect(first.place.municipalityCode == "698")
        #expect(requests > 0)
        #expect(second == first)
        #expect(http.requests == requests)
    }
}
