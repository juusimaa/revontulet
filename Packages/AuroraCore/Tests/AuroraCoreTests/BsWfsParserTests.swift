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
}
