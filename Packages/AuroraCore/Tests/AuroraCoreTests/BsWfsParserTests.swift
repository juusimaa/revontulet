import Foundation
import Testing
@testable import AuroraCore

@Suite("BsWfs simple parser")
struct BsWfsParserTests {
    @Test func parsesMagnetometerSample() throws {
        let elements = try BsWfsParser.parse(Fixtures.data("magnetometer-sample.xml"))

        #expect(elements.count == 219)
        let first = try #require(elements.first)
        #expect(first.coordinate == Coordinate(latitude: 62.254, longitude: 26.5965))
        #expect(first.time == utc("2026-10-22T16:23:10Z"))
        #expect(first.parameter == "MAGNX_PT10S_AVG")
        #expect(first.value == 91.2)
        #expect(Set(elements.map(\.parameter)) == ["MAGNX_PT10S_AVG", "MAGNY_PT10S_AVG", "MAGNZ_PT10S_AVG"])
    }

    @Test func parsesCloudObservations() throws {
        let name = try #require(Fixtures.first(prefix: "clouds-"))
        let elements = try BsWfsParser.parse(Fixtures.data(name))

        #expect(elements.count == 453)
        let first = try #require(elements.first)
        #expect(first.coordinate == Coordinate(latitude: 60.12735, longitude: 19.90038))
        #expect(first.parameter == "TotalCloudCover")
        #expect(first.value == 8)
        #expect(elements.allSatisfy { $0.value.map { (0...9).contains($0) } ?? true })
    }

    @Test func nanBecomesNil() throws {
        let elements = try BsWfsParser.parse(Fixtures.data("magnetometer-gaps.xml"))

        let missing = elements.filter { $0.value == nil }
        #expect(missing.count == 4)
        #expect(missing.allSatisfy { $0.parameter == "MAGNX_PT10S_AVG" })
    }

    @Test func exceptionReportThrows() throws {
        let data = try Fixtures.data("exception-report.xml")

        #expect(throws: FMIError.self) {
            try BsWfsParser.parse(data)
        }
        do {
            _ = try BsWfsParser.parse(data)
        } catch let FMIError.exceptionReport(message) {
            #expect(message.contains("Invalid time interval"))
        }
    }

    @Test func emptyCollectionGivesNoElements() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <wfs:FeatureCollection numberReturned="0" numberMatched="0"></wfs:FeatureCollection>
            """
        #expect(try BsWfsParser.parse(Data(xml.utf8)).isEmpty)
    }

    @Test func nonXMLIsMalformed() {
        #expect(throws: FMIError.malformedResponse) {
            try BsWfsParser.parse(Data("<html>Service unavailable</html>".utf8))
        }
    }

    // MARK: Cloud forecast (spec 003, research R5)

    @Test func cloudForecastGivesOneForecastPerZone() throws {
        let zones = try AlertZones.all()
        let fetchedAt = utc("2026-10-30T10:35:00Z")
        let forecasts = try BsWfsParser.cloudForecasts(
            Fixtures.data("outlook/cloud-forecast.xml"), zones: zones, fetchedAt: fetchedAt)

        #expect(forecasts.map(\.zoneID) == zones.map(\.id))
        for forecast in forecasts {
            #expect(forecast.fetchedAt == fetchedAt)
            #expect(forecast.hourly.count >= 60, "\(forecast.zoneID)")
            #expect(forecast.hourly.values.allSatisfy { (0...100).contains($0) })
            #expect(forecast.hourly.keys.allSatisfy { Int($0.timeIntervalSince1970).isMultiple(of: 3_600) })
        }
        #expect(forecasts.first { $0.zoneID == "OUJ" }?.hourly[utc("2026-10-30T11:00:00Z")] == 99.9)
    }

    @Test func cloudForecastMatchesNearestZoneWithin1KmAndDropsNaN() throws {
        let zones = try AlertZones.all()
        let ouj = try #require(zones.first { $0.id == "OUJ" }).station
        func element(_ lat: Double, _ lon: Double, _ time: String, _ value: String) -> String {
            """
            <wfs:member><BsWfs:BsWfsElement gml:id="x"><BsWfs:Location><gml:Point><gml:pos>\(lat) \(lon) </gml:pos>\
            </gml:Point></BsWfs:Location><BsWfs:Time>\(time)</BsWfs:Time><BsWfs:ParameterName>TotalCloudCover\
            </BsWfs:ParameterName><BsWfs:ParameterValue>\(value)</BsWfs:ParameterValue></BsWfs:BsWfsElement></wfs:member>
            """
        }
        let xml = #"<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0">"#
            // FMI moves the point to its grid: 0.005° is about 0.5 km.
            + element(ouj.latitude + 0.005, ouj.longitude, "2026-11-09T18:00:00Z", "12.5")
            + element(ouj.latitude, ouj.longitude, "2026-11-09T19:00:00Z", "NaN")
            // 0.05° north is about 5.6 km: no zone.
            + element(ouj.latitude + 0.05, ouj.longitude, "2026-11-09T18:00:00Z", "80")
            + "</wfs:FeatureCollection>"

        let forecasts = try BsWfsParser.cloudForecasts(Data(xml.utf8), zones: zones, fetchedAt: .now)

        #expect(forecasts.count == 1)
        #expect(forecasts.first?.zoneID == "OUJ")
        #expect(forecasts.first?.hourly == [utc("2026-11-09T18:00:00Z"): 12.5])
    }
}
