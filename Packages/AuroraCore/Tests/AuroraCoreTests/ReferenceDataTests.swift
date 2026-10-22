import Foundation
import Testing
@testable import AuroraCore

@Suite("Bundled reference data")
struct ReferenceDataTests {
    @Test func stationsMatchResearch() throws {
        let stations = try ReferenceData.loadStations()

        #expect(stations.map(\.id).sorted() == ["HAN", "IVA", "KEV", "KIL", "MEK", "MUO", "OUJ", "PEL", "RAN", "TAR"])
        for station in stations {
            #expect(station.yellowThreshold > 0, "\(station.id)")
            #expect(station.yellowThreshold < station.redThreshold, "\(station.id)")
        }
        let han = try #require(stations.first { $0.id == "HAN" })
        #expect(han.name == "Hankasalmi")
        #expect(han.yellowThreshold == 63)
        #expect(han.redThreshold == 140)
    }

    @Test func stationThresholdsMatchRecordedFMIValues() throws {
        // Recorded from fmi.fi by tools/record-fixtures.py; guards against silent drift.
        struct Threshold: Decodable { let yellow: Double; let red: Double }
        let recorded = try JSONDecoder().decode(
            [String: Threshold].self, from: Fixtures.data("reference-thresholds.json"))

        for station in try ReferenceData.loadStations() {
            let fmi = try #require(recorded[station.id], "\(station.id)")
            #expect(station.yellowThreshold == fmi.yellow, "\(station.id)")
            #expect(station.redThreshold == fmi.red, "\(station.id)")
        }
    }

    @Test func invalidThresholdsAreRejected() {
        let json = """
            [{"id":"BAD","name":"Bad","latitude":60,"longitude":25,"yellowThreshold":100,"redThreshold":50}]
            """
        #expect(throws: ReferenceDataError.invalidThresholds(stationID: "BAD")) {
            try ReferenceData.decodeStations(Data(json.utf8))
        }
    }

    @Test func municipalities() throws {
        let municipalities = try ReferenceData.loadMunicipalities()

        #expect(municipalities.count == 308)
        #expect(Set(municipalities.map(\.code)).count == 308)

        let helsinki = try #require(municipalities.first { $0.code == "091" })
        #expect(helsinki.nameFi == "Helsinki")
        #expect(helsinki.nameSv == "Helsingfors")

        let mariehamn = try #require(municipalities.first { $0.code == "478" })
        #expect(mariehamn.nameFi == "Maarianhamina")
        #expect(mariehamn.nameSv == "Mariehamn")
    }

    @Test func representativePointsLieInsideTheirMunicipality() throws {
        for municipality in try ReferenceData.loadMunicipalities() {
            #expect(municipality.boundingBox.contains(municipality.representativePoint), "\(municipality.code)")
            #expect(Geo.contains(municipality.polygons, municipality.representativePoint), "\(municipality.code)")
        }
    }
}
