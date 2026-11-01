import Foundation
import Testing
@testable import AuroraCore

@Suite("Nights (contracts/outlook-rules.md §1)")
struct NightsTests {
    static let ouj = Coordinate(latitude: 64.511, longitude: 27.227)
    static let kev = Coordinate(latitude: 69.756, longitude: 27.007)

    private func darkness(_ place: Coordinate, _ date: Date) -> Darkness {
        SolarPosition.darkness(latitude: place.latitude, longitude: place.longitude, at: date)
    }

    @Test func tonightWhileDarkIsThePeriodUnderWay() throws {
        let now = utc("2026-11-09T21:00:00Z")
        let (tonight, tomorrow) = Nights.nights(at: Self.ouj, now: now)

        let start = try #require(tonight.start), end = try #require(tonight.end)
        #expect(start < now && now < end)
        #expect(darkness(Self.ouj, start) != .tooLight)
        #expect(darkness(Self.ouj, start - 5 * 60) == .tooLight)
        #expect(darkness(Self.ouj, end) == .tooLight)
        #expect(darkness(Self.ouj, end - 5 * 60) != .tooLight)
        // Relevant hours: the Dark part from now on.
        #expect(tonight.relevantStart == now)
        #expect(tonight.reachesDark)
        let relevantEnd = try #require(tonight.relevantEnd)
        #expect(darkness(Self.ouj, relevantEnd - 5 * 60) == .dark)
        #expect(darkness(Self.ouj, relevantEnd) != .dark)

        let tomorrowStart = try #require(tomorrow.start)
        #expect(tomorrowStart > end)
        #expect(tomorrowStart.timeIntervalSince(start) > 20 * 3_600)
    }

    @Test func tonightInTheAfternoonIsTheNextDarkPeriod() throws {
        let now = utc("2026-11-09T10:00:00Z")  // 12:00 local, too light
        #expect(darkness(Self.ouj, now) == .tooLight)
        let (tonight, _) = Nights.nights(at: Self.ouj, now: now)

        let start = try #require(tonight.start)
        #expect(start > now)
        #expect(start.timeIntervalSince(now) < 6 * 3_600)
        let relevantStart = try #require(tonight.relevantStart)
        #expect(darkness(Self.ouj, relevantStart) == .dark)
        #expect(darkness(Self.ouj, relevantStart - 5 * 60) != .dark)
    }

    @Test func tomorrowStartsAfterTonightEnds() throws {
        let (tonight, tomorrow) = Nights.nights(at: Self.ouj, now: utc("2026-11-09T10:00:00Z"))
        let (next, _) = Nights.nights(at: Self.ouj, now: try #require(tonight.end))

        #expect(tomorrow == next)
        #expect(try #require(tomorrow.start) > (try #require(tonight.end)))
    }

    @Test func midsummerAtKevoIsTooLightForBothNights() {
        let (tonight, tomorrow) = Nights.nights(at: Self.kev, now: utc("2026-06-21T21:00:00Z"))

        #expect(tonight == .tooLight)
        #expect(tomorrow == .tooLight)
        #expect(tonight.start == nil && tonight.relevantStart == nil && !tonight.reachesDark)
    }

    /// In December the sun at Kevo stays below −6° for about 20 hours; no period is longer than 24.
    @Test func polarNightAtKevoIsCappedAt24Hours() throws {
        let (tonight, tomorrow) = Nights.nights(at: Self.kev, now: utc("2026-12-21T12:00:00Z"))

        for night in [tonight, tomorrow] {
            let start = try #require(night.start), end = try #require(night.end)
            #expect(end.timeIntervalSince(start) <= 24 * 3_600)
            #expect(end.timeIntervalSince(start) >= 18 * 3_600)
        }
    }

    /// Twilight-only nights (late April in the north): all twilight hours are relevant.
    @Test func twilightOnlyNightUsesAllItsHours() throws {
        let kilpisjarvi = Coordinate(latitude: 69.058, longitude: 20.775)
        let (tonight, _) = Nights.nights(at: kilpisjarvi, now: utc("2026-04-28T12:00:00Z"))

        #expect(!tonight.reachesDark)
        #expect(tonight.start != nil)
        #expect(tonight.relevantStart == tonight.start)
        #expect(tonight.relevantEnd == tonight.end)
    }

    /// The night's start date in Finnish time decides which storm-watch day covers it; the end of
    /// daylight saving (2026-10-25) and its start (2026-03-29) do not move it.
    @Test(arguments: [
        ("2026-10-24T12:00:00Z", "2026-10-24", "2026-10-25"),
        ("2026-10-25T01:30:00Z", "2026-10-24", "2026-10-25"),
        ("2026-03-28T12:00:00Z", "2026-03-28", "2026-03-29"),
        ("2026-03-29T00:30:00Z", "2026-03-28", "2026-03-29"),
    ])
    func localStartDateAcrossDaylightSavingChanges(now: String, tonight: String, tomorrow: String) throws {
        let nights = Nights.nights(at: Self.ouj, now: utc(now))

        #expect(nights.tonight.start.map(Nights.localDate) == tonight)
        #expect(nights.tomorrow.start.map(Nights.localDate) == tomorrow)
    }
}
