import Foundation
import Testing
@testable import AuroraCore

@Suite("Outlook service")
struct OutlookServiceTests {
    static let now = utc("2026-11-09T18:00:00Z")
    static let oulu = Place(coordinate: Coordinate(latitude: 65.01, longitude: 25.47),
                            municipalityCode: "564", source: .currentLocation)
    static let utsjoki = Place(coordinate: Coordinate(latitude: 69.9078, longitude: 27.0265),
                               municipalityCode: "890", source: .manual)

    static let solarWind = "propagated-solar-wind-1-hour.json"
    static let kpForecast = "noaa-planetary-k-index-forecast.json"
    static let alerts = "alerts.json"
    static let cloudForecast = "fmi::forecast::edited::weather::scandinavia::point::simple"

    static func offline() -> StubHTTPClient {
        StubHTTPClient([:])
    }

    @Test func cachedSnapshotMakesNoRequests() async throws {
        let http = Self.offline()
        let cache = InMemoryOutlookCache()
        _ = await OutlookService(http: http, cache: cache).refresh(for: Self.oulu, zoneID: "OUJ", at: Self.now, force: false)

        let other = Self.offline()
        let service = OutlookService(http: other, cache: cache)
        let cached = await service.cachedSnapshot()

        #expect(cached?.place == Self.oulu)
        #expect(other.requestedURLs.isEmpty)
    }

    @Test func emptyCacheGivesNoSnapshot() async {
        let http = Self.offline()
        #expect(await OutlookService(http: http, cache: InMemoryOutlookCache()).cachedSnapshot() == nil)
        #expect(http.requestedURLs.isEmpty)
    }

    /// Never throws: every request failing still gives a snapshot for the place, and it is stored.
    @Test func refreshWithEveryRequestFailingStillGivesASnapshot() async {
        let cache = InMemoryOutlookCache()
        let service = OutlookService(http: Self.offline(), cache: cache)

        let snapshot = await service.refresh(for: Self.utsjoki, zoneID: "KEV", at: Self.now, force: true)

        #expect(snapshot.place == Self.utsjoki)
        #expect(snapshot.zoneID == "KEV")
        #expect(snapshot.computedAt == Self.now)
        #expect(await cache.load() == snapshot)
    }

    // MARK: Solar wind (soon)

    /// The recorded quiet hour ends 2026-10-30 10:24; eight minutes later, as the live product lags.
    static let quietNow = utc("2026-10-30T10:32:00Z")
    static let kajaani = Place(coordinate: Coordinate(latitude: 64.22, longitude: 27.73),
                               municipalityCode: "205", source: .manual)

    /// A propagated solar wind body with 20 steady minutes, the newest `age` minutes before `now`.
    static func solarWind(bz: Double, speed: Double, now: Date, age: Double = 8) -> Data {
        var rows = [#"["time_tag","speed","density","bz","propagated_time_tag"]"#]
        for i in 0..<20 {
            let observed = now.addingTimeInterval(-(age + Double(19 - i)) * 60)
            rows.append("[\"\(UTCTime.format(observed))\",\(speed),4.0,\(bz),\"\(UTCTime.format(observed + 55 * 60))\"]")
        }
        return Data(("[" + rows.joined(separator: ",") + "]").utf8)
    }

    @Test func solarWindIsFetchedAtMostEveryFiveMinutes() async {
        let http = StubHTTPClient([Self.solarWind: .fixture("outlook/solar-wind-quiet.json")])
        let service = OutlookService(http: http, cache: InMemoryOutlookCache())

        for minutes in [0.0, 1, 4, 5, 9, 10] {
            _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + minutes * 60, force: false)
        }
        #expect(http.count(Self.solarWind) == 3)

        _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + 10 * 60 + 1, force: true)
        #expect(http.count(Self.solarWind) == 4)
    }

    @Test func quietHourGivesQuiet() async throws {
        let http = StubHTTPClient([Self.solarWind: .fixture("outlook/solar-wind-quiet.json")])
        let snapshot = await OutlookService(http: http, cache: InMemoryOutlookCache())
            .refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow, force: false)

        #expect(snapshot.soon.state == .quiet)
        #expect(snapshot.soon.dataTime == utc("2026-10-30T10:24:00Z"))
        #expect(!snapshot.soon.showsOnMainScreen)
        #expect(snapshot.samples?.fetchedAt == Self.quietNow)
        #expect(snapshot.samples?.value.count == 53)
    }

    @Test func failedFetchKeepsTheLastSamplesUntilTheyAreTooOld() async throws {
        let http = StubHTTPClient([Self.solarWind: .fixture("outlook/solar-wind-quiet.json")])
        let service = OutlookService(http: http, cache: InMemoryOutlookCache())
        let first = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow, force: false)

        http.set(Self.solarWind, .failure)
        let later = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + 6 * 60, force: false)
        #expect(later.samples == first.samples)
        #expect(later.soon.state == .quiet)

        // The newest sample (10:24) is more than 20 minutes old at 10:45.
        http.set(Self.solarWind, .data(Data("<html>500</html>".utf8), status: 500))
        let stale = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: utc("2026-10-30T10:45:00Z"), force: false)
        #expect(stale.soon.state == .unknown)
        #expect(stale.soon.dataTime == utc("2026-10-30T10:24:00Z"))
        #expect(stale.samples == first.samples)
        #expect(http.count(Self.solarWind) == 3)
    }

    /// Central band (OUJ): Likely from 5.0, kept while the driver is at least 3.75.
    @Test func hysteresisOnlyForTheSamePlace() async {
        let http = StubHTTPClient([Self.solarWind: .data(Self.solarWind(bz: -12, speed: 500, now: Self.now))])
        let service = OutlookService(http: http, cache: InMemoryOutlookCache())
        #expect(await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.now, force: false).soon.state == .likely)

        let later = Self.now + 5 * 60
        http.set(Self.solarWind, .data(Self.solarWind(bz: -8, speed: 500, now: later)))
        #expect(await service.refresh(for: Self.oulu, zoneID: "OUJ", at: later, force: false).soon.state == .likely)

        let other = OutlookService(http: StubHTTPClient([Self.solarWind: .data(Self.solarWind(bz: -12, speed: 500, now: Self.now))]),
                                   cache: InMemoryOutlookCache())
        _ = await other.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.now, force: false)
        let elsewhere = OutlookService(http: StubHTTPClient([Self.solarWind: .data(Self.solarWind(bz: -8, speed: 500, now: later))]),
                                       cache: InMemoryOutlookCache(await other.cachedSnapshot()))
        #expect(await elsewhere.refresh(for: Self.kajaani, zoneID: "OUJ", at: later, force: false).soon.state == .possible)
    }

    @Test func likelySignalIsShownAtNight() async {
        let http = StubHTTPClient([Self.solarWind: .data(Self.solarWind(bz: -12, speed: 500, now: Self.now))])
        let snapshot = await OutlookService(http: http, cache: InMemoryOutlookCache())
            .refresh(for: Self.oulu, zoneID: "OUJ", at: Self.now, force: false)

        #expect(snapshot.soon.state == .likely)
        #expect(snapshot.soon.arrivalMinutes == 30)
        #expect(snapshot.soon.showsOnMainScreen)
    }

    @Test func solarWindFailureLeavesTheRestOfTheSnapshot() async {
        let snapshot = await OutlookService(http: Self.offline(), cache: InMemoryOutlookCache())
            .refresh(for: Self.oulu, zoneID: "OUJ", at: Self.now, force: false)

        #expect(snapshot.soon == .unknown)
        #expect(snapshot.samples == nil)
        #expect(snapshot.place == Self.oulu)
    }

    // MARK: Kp forecast, watches and cloud forecast (outlook)

    /// The recorded inputs of 2026-10-30, fetched at 10:32 UTC.
    static func recorded() -> StubHTTPClient {
        StubHTTPClient([
            solarWind: .fixture("outlook/solar-wind-quiet.json"),
            kpForecast: .fixture("outlook/kp-forecast.json"),
            alerts: .fixture("outlook/alerts.json"),
            cloudForecast: .fixture("outlook/cloud-forecast.xml"),
        ])
    }

    @Test func outlookFromRecordedInputs() async throws {
        let snapshot = await OutlookService(http: Self.recorded(), cache: InMemoryOutlookCache())
            .refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow, force: false)
        let outlook = try #require(snapshot.outlook)

        #expect(snapshot.forecast?.blocks.count == 81)
        #expect(snapshot.watches?.value == [
            StormWatch(level: 1, days: ["2026-10-31", "2026-11-01"], issuedAt: utc("2026-10-29T19:10:00Z")),
        ])
        #expect(snapshot.clouds?.value.count == 10)
        #expect(outlook.tonight.availability == .available)
        #expect(outlook.tomorrow.availability == .available)
        // Tomorrow night starts on 2026-10-31, the day of the G1 watch.
        #expect(outlook.tonight.watchLevel == nil)
        #expect(outlook.tomorrow.watchLevel == 1)
        #expect(outlook.tonight.kpFetchedAt == Self.quietNow)
        #expect(outlook.tonight.cloudsFetchedAt == Self.quietNow)
    }

    @Test func forecastsAreFetchedOnlyWhenDue() async {
        let http = Self.recorded()
        let service = OutlookService(http: http, cache: InMemoryOutlookCache())
        func counts() -> [Int] { [Self.kpForecast, Self.alerts, "fmi::forecast"].map(http.count) }

        for minutes in [0.0, 5, 59] {
            _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + minutes * 60, force: false)
        }
        #expect(counts() == [1, 1, 1])
        _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + 60 * 60, force: false)
        #expect(counts() == [2, 2, 1])
        _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + 179 * 60, force: false)
        #expect(counts() == [3, 3, 1])
        _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + 180 * 60, force: false)
        #expect(counts() == [3, 3, 2])
        _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + 181 * 60, force: true)
        #expect(counts() == [4, 4, 3])
    }

    @Test func eachFetchFailsOnItsOwn() async throws {
        let http = Self.recorded()
        let service = OutlookService(http: http, cache: InMemoryOutlookCache())
        let first = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow, force: false)

        http.set(Self.kpForecast, .fixture("outlook/noaa-404.txt", status: 404))
        http.set(Self.alerts, .failure)
        let later = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow + 61 * 60, force: true)

        // Kp and alerts keep their last good inputs; solar wind and clouds were fetched again.
        #expect(later.forecast == first.forecast)
        #expect(later.watches == first.watches)
        #expect(later.samples?.fetchedAt == Self.quietNow + 61 * 60)
        #expect(later.clouds?.fetchedAt == Self.quietNow + 61 * 60)
        #expect(later.outlook?.tonight.availability == .available)

        // Only the Kp forecast ever failing: the soon signal and clouds are unaffected.
        let kpDown = Self.recorded()
        kpDown.set(Self.kpForecast, .failure)
        let snapshot = await OutlookService(http: kpDown, cache: InMemoryOutlookCache())
            .refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow, force: false)
        #expect(snapshot.soon.state == .quiet)
        #expect(snapshot.clouds?.value.count == 10)
        #expect(snapshot.forecast == nil)
        #expect(snapshot.outlook?.tonight.availability == .unavailable)
        #expect(snapshot.outlook?.tonight.clouds != .unknown)
    }

    /// A new launch offline: the cached inputs give an outlook for another place and a later time.
    @Test func cachedInputsAreRecomputedOffline() async throws {
        let cache = InMemoryOutlookCache()
        _ = await OutlookService(http: Self.recorded(), cache: cache)
            .refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow, force: false)

        let offline = Self.offline()
        let service = OutlookService(http: offline, cache: cache)
        let later = utc("2026-10-31T10:00:00Z")
        let snapshot = await service.refresh(for: Self.utsjoki, zoneID: "KEV", at: later, force: true)
        let outlook = try #require(snapshot.outlook)

        #expect(offline.requestedURLs.count == 4)
        #expect(snapshot.place == Self.utsjoki)
        #expect(outlook.computedAt == later)
        // Tonight is now the night of 2026-10-31, covered by the cached G1 watch.
        #expect(outlook.tonight.availability == .available)
        #expect(outlook.tonight.watchLevel == 1)
        #expect(outlook.tonight.cloudsFetchedAt == Self.quietNow)
        // The recorded solar wind is a day old.
        #expect(snapshot.soon.state == .unknown)
    }

    /// The recorded Kp forecast ends with the block of 2026-11-02 00 UTC.
    @Test func outlookUnavailableWhenNoBlockCoversTheNight() async throws {
        let snapshot = await OutlookService(http: Self.recorded(), cache: InMemoryOutlookCache())
            .refresh(for: Self.oulu, zoneID: "OUJ", at: utc("2026-11-03T12:00:00Z"), force: false)

        #expect(snapshot.outlook?.tonight.availability == .unavailable)
        #expect(snapshot.outlook?.tomorrow.availability == .unavailable)
    }

    @Test func requestsAreTheSameForEveryPlace() async {
        let http = Self.recorded()
        let service = OutlookService(http: http, cache: InMemoryOutlookCache())
        _ = await service.refresh(for: Self.oulu, zoneID: "OUJ", at: Self.quietNow, force: true)
        let first = Set(http.requestedURLs)
        _ = await service.refresh(for: Self.utsjoki, zoneID: "KEV", at: Self.quietNow, force: true)

        #expect(Set(http.requestedURLs) == first)
        #expect(first == [NOAARequests.propagatedSolarWind, NOAARequests.kpForecast, NOAARequests.alerts,
                          FMIRequests.cloudForecast(zones: try! AlertZones.all())])
    }

    @Test func snapshotRoundTrips() async throws {
        let snapshot = await OutlookService(http: Self.recorded(), cache: InMemoryOutlookCache())
            .refresh(for: Self.oulu, zoneID: "OUJ", at: Self.now, force: false)

        let decoded = try JSONDecoder().decode(OutlookSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }
}
