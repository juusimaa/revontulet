import Foundation
import Testing
@testable import AuroraCore

@Suite("NOAA parser (contracts/noaa-data.md)")
struct NOAAParserTests {
    // MARK: Propagated solar wind

    @Test func quietHour() throws {
        let samples = try NOAAParser.propagatedSolarWind(Fixtures.data("outlook/solar-wind-quiet.json"))

        #expect(samples.count == 53)
        #expect(samples.first?.time == utc("2026-10-30T09:32:00Z"))
        #expect(samples.last?.time == utc("2026-10-30T10:24:00Z"))
        #expect(samples.map(\.time) == samples.map(\.time).sorted())
        #expect(samples.first == SolarWindSample(
            time: utc("2026-10-30T09:32:00Z"), arrival: utc("2026-10-30T10:38:28Z"), bz: 2.29, speed: 329.6, density: 2.44))
    }

    @Test func columnsAreFoundByName() throws {
        // The same row with the columns in another order.
        let json = """
            [["propagated_time_tag","bz","density","speed","time_tag"],
             ["2026-10-30T10:30:00Z",-4.5,3.1,410.2,"2026-10-30T09:30:00Z"]]
            """
        let samples = try NOAAParser.propagatedSolarWind(Data(json.utf8))

        #expect(samples == [SolarWindSample(
            time: utc("2026-10-30T09:30:00Z"), arrival: utc("2026-10-30T10:30:00Z"), bz: -4.5, speed: 410.2, density: 3.1)])
    }

    @Test func gapsNullsAndDuplicates() throws {
        let samples = try NOAAParser.propagatedSolarWind(Fixtures.data("outlook/solar-wind-gaps.json"))

        // 54 rows: one without time_tag is dropped and the duplicated 10:22 minute is kept once.
        #expect(samples.count == 52)
        #expect(Set(samples.map(\.time)).count == samples.count)
        #expect(samples.map(\.time) == samples.map(\.time).sorted())
        let duplicate = try #require(samples.first { $0.time == utc("2026-10-30T10:22:00Z") })
        #expect(duplicate.bz == 0.54)
        let empty = try #require(samples.first { $0.time == utc("2026-10-30T10:10:00Z") })
        #expect(empty.bz == nil && empty.speed == nil && empty.density == nil)
        #expect(samples.first { $0.time == utc("2026-10-30T09:35:00Z") }?.bz == nil)
        #expect(samples.first { $0.time == utc("2026-10-30T09:37:00Z") }?.speed == nil)
    }

    @Test func stringValuesAndTimesWithoutZoneAreRead() throws {
        let json = """
            [["time_tag","speed","density","bz","propagated_time_tag"],
             ["2026-10-30 09:30:00.000","410.2","3.1","-4.5","2026-10-30 10:30:00.000"]]
            """
        let sample = try #require(try NOAAParser.propagatedSolarWind(Data(json.utf8)).first)

        #expect(sample.time == utc("2026-10-30T09:30:00Z"))
        #expect(sample.arrival == utc("2026-10-30T10:30:00Z"))
        #expect(sample.speed == 410.2)
    }

    @Test(arguments: ["time_tag", "bz", "speed", "propagated_time_tag"])
    func headerWithoutARequiredColumnThrows(missing: String) {
        let columns = ["time_tag", "speed", "density", "bz", "propagated_time_tag"].filter { $0 != missing }
        let header = "[" + columns.map { "\"\($0)\"" }.joined(separator: ",") + "]"

        #expect(throws: NOAAError.malformedResponse) {
            try NOAAParser.propagatedSolarWind(Data("[\(header)]".utf8))
        }
    }

    @Test(arguments: ["outlook/noaa-404.txt", "outlook/noaa-malformed.json"])
    func brokenBodiesThrow(fixture: String) throws {
        let data = try Fixtures.data(fixture)
        #expect(throws: NOAAError.malformedResponse) { try NOAAParser.propagatedSolarWind(data) }
    }

    // MARK: Kp forecast

    @Test func kpForecastObjectShape() throws {
        let forecast = try NOAAParser.kpForecast(Fixtures.data("outlook/kp-forecast.json"), fetchedAt: utc("2026-10-30T10:30:00Z"))

        #expect(forecast.blocks.count == 81)
        #expect(forecast.fetchedAt == utc("2026-10-30T10:30:00Z"))
        #expect(forecast.blocks.first == KpBlock(start: utc("2026-10-23T00:00:00Z"), kp: 1.67, kind: .observed))
        #expect(forecast.blocks.last == KpBlock(start: utc("2026-11-02T00:00:00Z"), kp: 2.67, kind: .predicted))
        #expect(forecast.blocks.filter { $0.kind == .estimated }.count == 5)
        #expect(forecast.blocks.filter { $0.kind == .predicted }.count == 17)
        #expect(forecast.blocks.map(\.start) == forecast.blocks.map(\.start).sorted())
        #expect(forecast.blocks.first { $0.start == utc("2026-10-31T00:00:00Z") }?.kp == 5.0)
    }

    @Test func kpForecastOldShapeGivesTheSameBlocks() throws {
        let fetchedAt = utc("2026-10-30T10:30:00Z")
        let new = try NOAAParser.kpForecast(Fixtures.data("outlook/kp-forecast.json"), fetchedAt: fetchedAt)
        let old = try NOAAParser.kpForecast(Fixtures.data("outlook/kp-forecast-old-shape.json"), fetchedAt: fetchedAt)

        #expect(old == new)
    }

    @Test func unknownKindIsPredictedAndUnorderedBlocksAreSorted() throws {
        let json = """
            [{"time_tag":"2026-11-01T03:00:00","kp":4.33,"observed":"modelled","noaa_scale":null},
             {"time_tag":"2026-11-01T00:00:00Z","kp":"3.67","observed":"estimated","noaa_scale":"G1"}]
            """
        let blocks = try NOAAParser.kpForecast(Data(json.utf8), fetchedAt: .now).blocks

        #expect(blocks == [
            KpBlock(start: utc("2026-11-01T00:00:00Z"), kp: 3.67, kind: .estimated),
            KpBlock(start: utc("2026-11-01T03:00:00Z"), kp: 4.33, kind: .predicted),
        ])
    }

    @Test(arguments: ["outlook/noaa-404.txt", "outlook/noaa-malformed.json", "outlook/alerts.json"])
    func brokenKpForecastThrows(fixture: String) throws {
        let data = try Fixtures.data(fixture)
        #expect(throws: NOAAError.malformedResponse) { try NOAAParser.kpForecast(data, fetchedAt: .now) }
    }

    // MARK: Storm watches

    private func watches(at now: String) throws -> [StormWatch] {
        try NOAAParser.stormWatches(Fixtures.data("outlook/alerts.json"), now: utc(now))
    }

    /// The newest watch (2026-10-29 19:10, G1 for Oct 31 and Nov 01) supersedes the older ones;
    /// its "None" day is dropped.
    @Test func newestWatchSupersedesOlderOnes() throws {
        #expect(try watches(at: "2026-10-30T12:00:00Z") == [
            StormWatch(level: 1, days: ["2026-10-31", "2026-11-01"], issuedAt: utc("2026-10-29T19:10:00Z")),
        ])
    }

    /// The G1 and G2 levels come from the day lines of the 2026-10-09 16:36 WATA30 watch; days
    /// before today (UTC) are dropped.
    @Test func levelsComeFromTheDayLines() throws {
        #expect(try watches(at: "2026-10-10T12:00:00Z") == [
            StormWatch(level: 1, days: ["2026-10-10"], issuedAt: utc("2026-10-09T16:36:00Z")),
            StormWatch(level: 2, days: ["2026-10-11"], issuedAt: utc("2026-10-09T16:36:00Z")),
        ])
    }

    /// The cancellation of 2026-10-11 17:02 removes the G2 day; messages issued after now are ignored.
    @Test func laterCancellationRemovesItsDays() throws {
        #expect(try watches(at: "2026-10-11T12:00:00Z") == [
            StormWatch(level: 2, days: ["2026-10-11"], issuedAt: utc("2026-10-09T16:36:00Z")),
        ])
        #expect(try watches(at: "2026-10-11T18:00:00Z").isEmpty)
    }

    private static func alerts(_ messages: [(issued: String, message: String)]) -> Data {
        let objects = messages.map { ["product_id": "A20F", "issue_datetime": $0.issued, "message": $0.message] }
        return try! JSONSerialization.data(withJSONObject: objects)
    }

    @Test func issueTimeFallsBackToIssueDatetime() throws {
        let data = Self.alerts([("2026-11-02 08:15:30.100", """
            Space Weather Message Code: WATA30\r\nSerial Number: 300\r\n\r\nWATCH: Geomagnetic Storm Category G2 Predicted
            Highest Storm Level Predicted by Day:
            Nov 03:  G2 (Moderate)   Nov 04:  G1 (Minor)   Nov 05:  None (Below G1)
            """)])

        #expect(try NOAAParser.stormWatches(data, now: utc("2026-11-02T12:00:00Z")) == [
            StormWatch(level: 1, days: ["2026-11-04"], issuedAt: utc("2026-11-02T08:15:30Z")),
            StormWatch(level: 2, days: ["2026-11-03"], issuedAt: utc("2026-11-02T08:15:30Z")),
        ])
    }

    @Test func yearRollsOverFromDecemberToJanuary() throws {
        let data = Self.alerts([("2026-12-30 20:05:00.000", """
            Space Weather Message Code: WATA20
            Issue Time: 2026 Dec 30 2005 UTC

            WATCH: Geomagnetic Storm Category G1 Predicted
            Highest Storm Level Predicted by Day:
            Dec 31:  G1 (Minor)   Jan 01:  G1 (Minor)   Jan 02:  None (Below G1)
            """)])

        #expect(try NOAAParser.stormWatches(data, now: utc("2026-12-31T06:00:00Z")) == [
            StormWatch(level: 1, days: ["2026-12-31", "2027-01-01"], issuedAt: utc("2026-12-30T20:05:00Z")),
        ])
    }

    @Test func unrecognisedWatchMessageIsSkipped() throws {
        let data = Self.alerts([
            ("2026-11-02 08:00:00.000", "Space Weather Message Code: WATA50\nSomething else entirely"),
            ("2026-11-01 08:00:00.000", """
                Space Weather Message Code: WATA20
                Issue Time: 2026 Nov 01 0800 UTC
                WATCH: Geomagnetic Storm Category G1 Predicted
                Highest Storm Level Predicted by Day:
                Nov 02:  G1 (Minor)   Nov 03:  None (Below G1)   Nov 04:  None (Below G1)
                """),
        ])

        #expect(try NOAAParser.stormWatches(data, now: utc("2026-11-02T09:00:00Z")) == [
            StormWatch(level: 1, days: ["2026-11-02"], issuedAt: utc("2026-11-01T08:00:00Z")),
        ])
    }

    @Test(arguments: ["outlook/noaa-404.txt", "outlook/noaa-malformed.json"])
    func brokenAlertsThrow(fixture: String) throws {
        let data = try Fixtures.data(fixture)
        #expect(throws: NOAAError.malformedResponse) { try NOAAParser.stormWatches(data, now: .now) }
    }
}
