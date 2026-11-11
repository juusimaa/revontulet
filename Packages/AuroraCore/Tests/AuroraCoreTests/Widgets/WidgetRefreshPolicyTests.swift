import Foundation
import Testing
@testable import AuroraCore

@Suite("WidgetRefreshPolicy")
struct WidgetRefreshPolicyTests {
    private static let oulu = Coordinate(latitude: 65.0121, longitude: 25.4651)
    private static let utsjoki = Coordinate(latitude: 69.9078, longitude: 27.0265)
    private static let ouluPlace = Place(coordinate: oulu, municipalityCode: "564", source: .manual)
    private static let helsinkiPlace = Place(coordinate: Coordinate(latitude: 60.1699, longitude: 24.9384),
                                             municipalityCode: "091", source: .manual)
    private static let now = utc("2026-10-22T16:40:00Z")
    private static let station = Station(
        id: "OUJ", name: "Oulujärvi", latitude: 64.52, longitude: 27.23, yellowThreshold: 55, redThreshold: 165)

    private static func result(place: Place = ouluPlace, computedAt: Date) -> AuroraResult {
        AuroraResult(
            place: place,
            chance: Chance(level: .low, limitingFactor: .activity, cloudsIncluded: true),
            reading: StationReading(station: station, r: 10, measuredAt: computedAt, activity: .unlikely),
            distanceToStationKm: 50, usedMoreDistantStation: false, darkness: .dark, clouds: .unknown,
            moon: MoonState(altitude: -10, illuminatedFraction: 0.1, phase: .waxingCrescent, isBright: false),
            computedAt: computedAt)
    }

    private static func outlook(place: Place = ouluPlace, computedAt: Date) -> OutlookSnapshot {
        OutlookSnapshot(place: place, zoneID: "oulu", computedAt: computedAt)
    }

    // MARK: resultNeedsFetch

    /// Boundary: a result is due once its age reaches 5 minutes (age >= 5:00).
    @Test(arguments: [(299.0, false), (300.0, true), (301.0, true), (0.0, false)])
    func resultAge(age: Double, due: Bool) {
        let cached = Self.result(computedAt: Self.now.addingTimeInterval(-age))
        #expect(WidgetRefreshPolicy.resultNeedsFetch(cached: cached, place: Self.ouluPlace, now: Self.now) == due)
    }

    @Test func resultNoCache() {
        #expect(WidgetRefreshPolicy.resultNeedsFetch(cached: nil, place: Self.ouluPlace, now: Self.now))
    }

    @Test func resultOtherMunicipality() {
        let cached = Self.result(computedAt: Self.now.addingTimeInterval(-10))
        #expect(WidgetRefreshPolicy.resultNeedsFetch(cached: cached, place: Self.helsinkiPlace, now: Self.now))
    }

    @Test func resultFromTheFuture() {
        let cached = Self.result(computedAt: Self.now.addingTimeInterval(1))
        #expect(WidgetRefreshPolicy.resultNeedsFetch(cached: cached, place: Self.ouluPlace, now: Self.now))
    }

    // MARK: outlookNeedsFetch

    @Test(arguments: [(299.0, false), (300.0, true), (301.0, true)])
    func outlookAge(age: Double, due: Bool) {
        let cached = Self.outlook(computedAt: Self.now.addingTimeInterval(-age))
        #expect(WidgetRefreshPolicy.outlookNeedsFetch(cached: cached, place: Self.ouluPlace, now: Self.now) == due)
    }

    @Test func outlookNoCache() {
        #expect(WidgetRefreshPolicy.outlookNeedsFetch(cached: nil, place: Self.ouluPlace, now: Self.now))
    }

    @Test func outlookOtherMunicipality() {
        let cached = Self.outlook(computedAt: Self.now.addingTimeInterval(-10))
        #expect(WidgetRefreshPolicy.outlookNeedsFetch(cached: cached, place: Self.helsinkiPlace, now: Self.now))
    }

    @Test func outlookFromTheFuture() {
        let cached = Self.outlook(computedAt: Self.now.addingTimeInterval(1))
        #expect(WidgetRefreshPolicy.outlookNeedsFetch(cached: cached, place: Self.ouluPlace, now: Self.now))
    }

    // MARK: staleMoment

    @Test func staleMoment() {
        #expect(WidgetRefreshPolicy.staleMoment(measuredAt: Self.now) == Self.now.addingTimeInterval(30 * 60))
    }

    // MARK: nextReload

    @Test func darkDecemberNightInOuluReloadsInFifteenMinutes() {
        let now = Self.utc("2026-12-15T20:00:00Z")
        #expect(WidgetRefreshPolicy.nextReload(after: now, at: Self.oulu) == now.addingTimeInterval(15 * 60))
    }

    @Test func polarSummerIsCappedAtThreeHours() {
        let now = Self.utc("2026-06-21T10:00:00Z")
        #expect(SolarPosition.darkness(latitude: Self.utsjoki.latitude, longitude: Self.utsjoki.longitude,
                                       at: now) == .tooLight)
        #expect(WidgetRefreshPolicy.nextReload(after: now, at: Self.utsjoki) == now.addingTimeInterval(3 * 3600))
    }

    @Test func duskApproachingReloadsFifteenMinutesBeforeDark() {
        let dusk = Self.firstNotTooLight(from: Self.utc("2026-09-10T12:00:00Z"))
        // Steps at +60 min is still too light (dusk - 10 min), +75 min is not: reload at +60 min.
        let now = dusk.addingTimeInterval(-70 * 60)
        #expect(WidgetRefreshPolicy.nextReload(after: now, at: Self.oulu) == now.addingTimeInterval(60 * 60))
    }

    @Test func duskVeryCloseIsNotEarlierThanFifteenMinutes() {
        let dusk = Self.firstNotTooLight(from: Self.utc("2026-09-10T12:00:00Z"))
        let now = dusk.addingTimeInterval(-5 * 60)
        #expect(WidgetRefreshPolicy.nextReload(after: now, at: Self.oulu) == now.addingTimeInterval(15 * 60))
    }

    @Test func duskFarAwayIsCappedAtThreeHours() {
        let dusk = Self.firstNotTooLight(from: Self.utc("2026-09-10T12:00:00Z"))
        let now = dusk.addingTimeInterval(-6 * 3600)
        #expect(WidgetRefreshPolicy.nextReload(after: now, at: Self.oulu) == now.addingTimeInterval(3 * 3600))
    }

    @Test func alwaysStrictlyAfterNowAndWithinThreeHours() {
        let start = Self.utc("2026-01-01T00:00:00Z")
        for coordinate in [Self.oulu, Self.utsjoki, Self.helsinkiPlace.coordinate] {
            for index in 0..<(365 * 2) {
                let now = start.addingTimeInterval(Double(index) * 12 * 3600 + 137)
                let next = WidgetRefreshPolicy.nextReload(after: now, at: coordinate)
                #expect(next >= now.addingTimeInterval(15 * 60))
                #expect(next <= now.addingTimeInterval(3 * 3600))
            }
        }
    }

    /// The first minute from `date` at which it is no longer too light at Oulu.
    private static func firstNotTooLight(from date: Date) -> Date {
        var time = date
        while SolarPosition.darkness(latitude: oulu.latitude, longitude: oulu.longitude, at: time) == .tooLight {
            time = time.addingTimeInterval(60)
        }
        return time
    }

    private static func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
