import Foundation
@testable import AuroraCore

/// Recorded magnetometer data (`magnetometer-<station>-<time>.csv`), three hours per station.
enum MagnetometerFixtures {
    /// All recorded samples, keyed by station code.
    static func samplesByStation() throws -> [String: [MagnetometerSample]] {
        guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw Fixtures.FixtureError.missing("Fixtures")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("magnetometer-") && $0.hasSuffix(".csv") }
        var result: [String: [MagnetometerSample]] = [:]
        for file in files {
            let station = file.split(separator: "-")[1]
            result[String(station)] = try samples(csv: Fixtures.data(file), stationID: String(station))
        }
        return result
    }

    static func samples(csv data: Data, stationID: String) throws -> [MagnetometerSample] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("time") }
            .map { line in
                let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                func value(_ text: String) -> Double? { Double(text).flatMap { $0.isNaN ? nil : $0 } }
                return MagnetometerSample(
                    stationID: stationID, time: utc(fields[0]),
                    x: value(fields[1]), y: value(fields[2]), z: value(fields[3]))
            }
    }

    /// A BsWfs "simple" magnetometer response for all recorded stations, covering the 12 minutes
    /// that `FMIRequests.magnetometer(now:)` would ask for.
    static func response(now: Date) throws -> Data {
        let stations = Dictionary(uniqueKeysWithValues: try ReferenceData.loadStations().map { ($0.id, $0) })
        let start = now.addingTimeInterval(-12 * 60)
        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0">

            """
        for (stationID, samples) in try samplesByStation().sorted(by: { $0.key < $1.key }) {
            guard let station = stations[stationID] else { continue }
            for sample in samples where sample.time >= start && sample.time <= now {
                for (name, value) in [("MAGNX_PT10S_AVG", sample.x), ("MAGNY_PT10S_AVG", sample.y), ("MAGNZ_PT10S_AVG", sample.z)] {
                    xml += """
                        <wfs:member><BsWfs:BsWfsElement gml:id="x">\
                        <BsWfs:Location><gml:Point><gml:pos>\(station.latitude) \(station.longitude) </gml:pos></gml:Point></BsWfs:Location>\
                        <BsWfs:Time>\(UTCTime.format(sample.time))</BsWfs:Time>\
                        <BsWfs:ParameterName>\(name)</BsWfs:ParameterName>\
                        <BsWfs:ParameterValue>\(value.map { String($0) } ?? "NaN")</BsWfs:ParameterValue>\
                        </BsWfs:BsWfsElement></wfs:member>

                        """
                }
            }
        }
        xml += "</wfs:FeatureCollection>\n"
        return Data(xml.utf8)
    }
}
