import AuroraCore
import Foundation
import Testing
import WidgetKit
@testable import Revontulet

/// The provider builds entries from injected stores. The "no network request" part of T036 arrives with
/// the data loader in phase 6: the provider has no HTTP client yet.
@Suite("Widget provider")
struct WidgetProviderTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let station = Station(
        id: "KEV", name: "Kevo", latitude: 69.761, longitude: 27.01, yellowThreshold: 55, redThreshold: 165)

    private static func result(code: String, r: Double? = 120, ageMin: Double) -> AuroraResult {
        let measured = now.addingTimeInterval(-ageMin * 60)
        return AuroraResult(
            place: Place(coordinate: Coordinate(latitude: 65.0, longitude: 25.5), municipalityCode: code, source: .manual),
            chance: Chance(level: .moderate, limitingFactor: nil, cloudsIncluded: true),
            reading: StationReading(station: station, r: r, measuredAt: measured, activity: .probable),
            distanceToStationKm: 16.4, usedMoreDistantStation: false, darkness: .dark,
            clouds: CloudCover(condition: .clear),
            moon: MoonState(altitude: -10, illuminatedFraction: 0.2, phase: .waxingCrescent, isBright: false),
            computedAt: measured)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func hit() { lock.withLock { value += 1 } }
    }

    private static func build(
        _ selection: PlaceSelection, _ cached: AuroraResult?, family: WidgetFamily = .systemSmall,
        fetched: AuroraResult? = nil, fetchDelay: Duration = .zero, budget: TimeInterval = 8,
        results: Counter = Counter(), outlooks: Counter = Counter(), cancels: Counter = Counter()
    ) async -> (entries: [AuroraEntry], nextReload: Date) {
        await AuroraProvider(
            loadResult: { cached }, loadOutlook: { nil },
            fetchResult: { _, _ in
                results.hit()
                try? await Task.sleep(for: fetchDelay)
                return fetched
            },
            fetchOutlook: { _, _ in outlooks.hit(); return nil },
            cancelFetch: { cancels.hit() },
            fetchBudget: budget,
            readSelection: { selection },
            now: { now }, prefersSwedish: false
        ).build(family: family)
    }

    @Test("no place never fetches")
    func noPlaceNoFetch() async {
        let results = Counter()
        _ = await Self.build(.currentLocation, nil, results: results)
        #expect(results.count == 0)
    }

    @Test("a fetched fresh result replaces the stale cache")
    func fetchedWins() async throws {
        let fresh = Self.result(code: "564", ageMin: 2)
        let built = await Self.build(.municipality(code: "564"), Self.result(code: "564", ageMin: 31), fetched: fresh)
        guard case .current(let s) = built.entries[0].state else { throw Failure() }
        #expect(!s.isStale)
    }

    @Test("a failed fetch falls back to the stale cache")
    func fetchFailsUsesCache() async throws {
        let built = await Self.build(.municipality(code: "564"), Self.result(code: "564", ageMin: 31))
        guard case .stale = built.entries[0].state else { throw Failure() }
    }

    @Test("the outlook is fetched only for the medium widget")
    func outlookOnlyMedium() async {
        for (family, expected) in [(WidgetFamily.systemSmall, 0), (.accessoryInline, 0), (.systemMedium, 1)] {
            let outlooks = Counter()
            _ = await Self.build(.municipality(code: "564"), Self.result(code: "564", ageMin: 5),
                                 family: family, outlooks: outlooks)
            #expect(outlooks.count == expected)
        }
    }

    @Test("a slow fetch is cancelled at the budget and the cache is used")
    func budget() async throws {
        let cancels = Counter()
        let start = Date()
        let built = await Self.build(
            .municipality(code: "564"), Self.result(code: "564", ageMin: 31),
            fetched: Self.result(code: "564", ageMin: 2), fetchDelay: .seconds(5), budget: 0.1, cancels: cancels)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(cancels.count == 1)
        guard case .stale = built.entries[0].state else { throw Failure() }
    }

    @Test("current location with no cache is noPlace (also outside Finland, where nothing is stored)")
    func noCacheCurrentLocation() async {
        let built = await Self.build(.currentLocation, nil)
        #expect(built.entries.count == 1)
        #expect(built.entries[0].state == .noPlace)
        #expect(built.nextReload == Self.now.addingTimeInterval(AuroraProvider.noPlaceDelay))
    }

    @Test("unknown municipality code is noPlace")
    func unknownMunicipality() async {
        let built = await Self.build(.municipality(code: "999999"), nil)
        #expect(built.entries.map(\.state) == [.noPlace])
    }

    @Test("result older than 30 min is stale")
    func staleResult() async throws {
        let built = await Self.build(.municipality(code: "564"), Self.result(code: "564", ageMin: 31))
        #expect(built.entries.count == 1)
        guard case .stale(let s) = built.entries[0].state else { throw Failure() }
        #expect(s.isStale)
    }

    @Test("result without R is noData with a place name")
    func noR() async {
        let built = await Self.build(.municipality(code: "564"), Self.result(code: "564", r: nil, ageMin: 5))
        #expect(built.entries.count == 1)
        #expect(built.entries[0].state == .noData)
        #expect(!built.entries[0].placeName.isEmpty)
    }

    @Test("another place's cached result is never shown")
    func otherPlace() async {
        let built = await Self.build(.municipality(code: "564"), Self.result(code: "698", ageMin: 5))
        #expect(built.entries.map(\.state) == [.noData])
    }

    @Test("fresh result gets a second entry that turns stale at measuredAt + 30 min")
    func freshThenStale() async throws {
        let cached = Self.result(code: "564", ageMin: 10)
        let built = await Self.build(.municipality(code: "564"), cached)
        #expect(built.entries.count == 2)
        guard case .current(let first) = built.entries[0].state,
              case .stale(let second) = built.entries[1].state else { throw Failure() }
        #expect(built.entries[0].date == Self.now)
        #expect(!first.isStale)
        #expect(built.entries[1].date == cached.reading.measuredAt.addingTimeInterval(30 * 60))
        #expect(second.isStale)
    }

    @Test("exactly 30 min old is still current, with no second entry")
    func exactlyThirty() async throws {
        let built = await Self.build(.municipality(code: "564"), Self.result(code: "564", ageMin: 30))
        #expect(built.entries.count == 1)
        guard case .current = built.entries[0].state else { throw Failure() }
    }

    @Test("current location uses the cached result's place")
    func currentLocationWithCache() async throws {
        let built = await Self.build(.currentLocation, Self.result(code: "698", ageMin: 5))
        guard case .current = built.entries[0].state else { throw Failure() }
        #expect(!built.entries[0].placeName.isEmpty)
    }

    private struct Failure: Error {}
}
