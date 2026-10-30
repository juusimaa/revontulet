import Foundation
import Testing
@testable import AuroraCore

@Suite("Outlook rules (contracts/outlook-rules.md)")
struct OutlookCalculatorTests {
    static let ouj = Coordinate(latitude: 64.511, longitude: 27.227)
    static let kev = Coordinate(latitude: 69.756, longitude: 27.007)
    /// 14:00 in Finland: tonight is the next dark period.
    static let afternoon = utc("2026-11-09T12:00:00Z")
    static let fetchedAt = utc("2026-11-09T11:30:00Z")

    /// Kp `value` in every 3-hour block from the day before `from` for four days.
    static func kp(_ value: Double, from: String = "2026-11-09") -> KpForecast {
        let start = utc("\(from)T00:00:00Z") - 86_400
        return KpForecast(
            blocks: (0..<32).map { KpBlock(start: start + Double($0) * 3 * 3_600, kp: value, kind: .predicted) },
            fetchedAt: fetchedAt)
    }

    /// `percent` cloud cover every hour from the day before `from` for four days.
    static func clouds(_ percent: Double, from: String = "2026-11-09") -> CloudForecast {
        let start = utc("\(from)T00:00:00Z") - 86_400
        return CloudForecast(
            zoneID: "OUJ", hourly: Dictionary(uniqueKeysWithValues: (0..<96).map { (start + Double($0) * 3_600, percent) }),
            fetchedAt: fetchedAt)
    }

    static func watch(_ level: Int, _ day: String) -> StormWatch {
        StormWatch(level: level, days: [day], issuedAt: utc("2026-11-08T19:00:00Z"))
    }

    private func tonight(
        at place: Coordinate = ouj, band: Band = .central, now: Date = afternoon, kp: KpForecast?,
        watches: [StormWatch] = [], clouds: CloudForecast?
    ) -> NightOutlook {
        OutlookCalculator.outlook(place: place, band: band, now: now, kp: kp, watches: watches, clouds: clouds).tonight
    }

    // MARK: Reference cases 1–11

    @Test func case1SomeActivity() {
        let night = tonight(kp: Self.kp(3), clouds: Self.clouds(10))
        #expect(night.chance?.level == .moderate)
        #expect(night.reason == .chance(.someActivity))
        #expect(night.activity == .possible)
        #expect(night.clouds == .clear)
        #expect(!night.moon)
    }

    @Test func case2GoodConditions() {
        let night = tonight(kp: Self.kp(6), clouds: Self.clouds(10))
        #expect(night.chance?.level == .high)
        #expect(night.reason == .chance(.goodConditions))
    }

    @Test func case3LowActivity() {
        let night = tonight(kp: Self.kp(2), clouds: Self.clouds(10))
        #expect(night.chance?.level == .low)
        #expect(night.reason == .chance(.lowActivity))
    }

    @Test func case4BrightMoon() {
        let night = tonight(now: utc("2026-11-24T12:00:00Z"), kp: Self.kp(6, from: "2026-11-24"),
                            clouds: Self.clouds(10, from: "2026-11-24"))
        #expect(night.moon)
        #expect(night.chance?.level == .moderate)
        #expect(night.reason == .chance(.brightMoon))
    }

    @Test func case5StormWatchRaisesActivity() {
        let night = tonight(kp: Self.kp(3), watches: [Self.watch(2, "2026-11-09")], clouds: Self.clouds(10))
        #expect(night.maxKp == 6)
        #expect(night.watchLevel == 2)
        #expect(night.chance?.level == .high)
        #expect(night.reason == .stormWatch)
    }

    @Test func case6Overcast() {
        let night = tonight(kp: Self.kp(6), clouds: Self.clouds(95))
        #expect(night.chance?.level == Optional(ChanceLevel.none))
        #expect(night.reason == .chance(.overcast))
        #expect(night.clouds == .overcast)
        #expect(night.meanCloudPercent == 95)
    }

    @Test func case7NoCloudForecast() {
        let night = tonight(kp: Self.kp(6), clouds: nil)
        #expect(night.chance == Chance(level: .high, limitingFactor: nil, cloudsIncluded: false))
        #expect(night.reason == .chance(.goodConditions))
        #expect(night.cloudsFetchedAt == nil)
    }

    @Test func case8MidsummerAtKevo() {
        let outlook = OutlookCalculator.outlook(
            place: Self.kev, band: .north, now: utc("2026-06-21T12:00:00Z"), kp: Self.kp(6, from: "2026-06-21"),
            watches: [], clouds: nil)
        for night in [outlook.tonight, outlook.tomorrow] {
            #expect(night.availability == .tooLight)
            #expect(night.chance?.level == Optional(ChanceLevel.none))
            #expect(night.reason == .chance(.tooLight))
            #expect(night.activity == nil)
        }
    }

    /// 03:00 in Finland on 2026-11-10, the night under way: the 21–24 UTC block has ended.
    @Test func case9BlocksThatEndedAreIgnored() {
        var blocks = [KpBlock(start: utc("2026-11-09T21:00:00Z"), kp: 6, kind: .observed)]
        blocks += (0..<8).map { KpBlock(start: utc("2026-11-10T00:00:00Z") + Double($0) * 3 * 3_600, kp: 2, kind: .predicted) }
        let night = tonight(now: utc("2026-11-10T01:00:00Z"), kp: KpForecast(blocks: blocks, fetchedAt: Self.fetchedAt),
                            clouds: Self.clouds(10))
        #expect(night.maxKp == 2)
        #expect(night.chance?.level == .low)
        #expect(night.reason == .chance(.lowActivity))
    }

    @Test func case10NoKpForecastIsUnavailable() {
        let outlook = OutlookCalculator.outlook(place: Self.ouj, band: .central, now: Self.afternoon, kp: nil,
                                                watches: [], clouds: Self.clouds(10))
        for night in [outlook.tonight, outlook.tomorrow] {
            #expect(night.availability == .unavailable)
            #expect(night.chance == nil)
            #expect(night.reason == nil)
        }
    }

    /// A watch day covers the night that starts on that date in Finland, not the early hours of
    /// the night before.
    @Test func case11WatchForTomorrowOnly() {
        let outlook = OutlookCalculator.outlook(place: Self.ouj, band: .central, now: Self.afternoon, kp: Self.kp(2),
                                                watches: [Self.watch(2, "2026-11-10")], clouds: Self.clouds(10))
        #expect(outlook.tonight.chance?.level == .low)
        #expect(outlook.tonight.reason == .chance(.lowActivity))
        #expect(outlook.tonight.watchLevel == nil)
        #expect(outlook.tomorrow.chance?.level == .high)
        #expect(outlook.tomorrow.reason == .stormWatch)
        #expect(outlook.tomorrow.watchLevel == 2)
    }

    // MARK: Details

    /// A watch that does not change the activity does not replace the reason.
    @Test func watchThatDecidesNothingKeepsTheChanceReason() {
        let night = tonight(kp: Self.kp(6), watches: [Self.watch(1, "2026-11-09")], clouds: Self.clouds(10))
        #expect(night.watchLevel == 1)
        #expect(night.maxKp == 6)
        #expect(night.reason == .chance(.goodConditions))
    }

    @Test(arguments: [(30.0, CloudCondition.clear), (45, .partly), (50, .partly), (80, .partly), (82, .overcast)])
    func cloudMeanToOctas(percent: Double, condition: CloudCondition) {
        #expect(tonight(kp: Self.kp(6), clouds: Self.clouds(percent)).clouds == condition)
    }

    @Test func cloudsUnknownWhenFewerThanHalfTheHoursHaveAValue() throws {
        let full = Self.clouds(10)
        let night = tonight(kp: Self.kp(6), clouds: full)
        let start = try #require(night.night.relevantStart), end = try #require(night.night.relevantEnd)
        // Keep only the first third of the relevant hours.
        let cutoff = start + end.timeIntervalSince(start) / 3
        let sparse = CloudForecast(zoneID: "OUJ", hourly: full.hourly.filter { $0.key < cutoff }, fetchedAt: Self.fetchedAt)

        #expect(tonight(kp: Self.kp(6), clouds: sparse).clouds == .unknown)
        #expect(tonight(kp: Self.kp(6), clouds: sparse).chance?.cloudsIncluded == false)
    }

    @Test func fetchTimesAreCarried() {
        let night = tonight(kp: Self.kp(4), clouds: Self.clouds(10))
        #expect(night.kpFetchedAt == Self.fetchedAt)
        #expect(night.cloudsFetchedAt == Self.fetchedAt)
        #expect(night.availability == .available)
        #expect(night.darkness == .dark)
    }

    @Test func computesQuickly() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = OutlookCalculator.outlook(place: Self.ouj, band: .central, now: Self.afternoon, kp: Self.kp(4),
                                          watches: [], clouds: Self.clouds(10))
        }
        #expect(elapsed < .milliseconds(50))
    }
}
