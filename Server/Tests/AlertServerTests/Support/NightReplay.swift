import AuroraCore
import Foundation

/// Answers FMI requests from a night recorded for the core's tests
/// (`Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/alerts/<night>/`), building each
/// response for the request's own time window.
///
/// Times in the fixtures and in FMI URLs share the format `yyyy-MM-ddTHH:mm:ssZ`, so they are
/// compared as strings.
struct NightReplayHTTPClient: HTTPClient {
    struct Expected: Decodable, Hashable {
        var zone: String
        var level: String
        var time: String
    }

    let start: Date
    let end: Date
    let expected: [Expected]
    /// (time, latitude, longitude, x, y, z) per magnetometer row; empty strings for NaN.
    private let magnetometer: [(String, Double, Double, String, String, String)]
    /// (time, latitude, longitude, octas) per cloud row.
    private let clouds: [(String, String, String, String)]

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/alerts")

    init(night: String) throws {
        let folder = Self.fixtures.appendingPathComponent(night)
        struct Window: Decodable { var start: Date; var end: Date }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let window = try decoder.decode(Window.self, from: Data(contentsOf: folder.appendingPathComponent("night.json")))
        start = window.start
        end = window.end
        expected = try JSONDecoder().decode([Expected].self, from: Data(contentsOf: folder.appendingPathComponent("expected.json")))

        func rows(_ file: String) throws -> [[String]] {
            try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .filter { !$0.hasPrefix("#") && !$0.hasPrefix("time") }
                .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        }
        var magnetometer: [(String, Double, Double, String, String, String)] = []
        for station in try ReferenceData.loadStations() {
            for row in try rows("magnetometer-\(station.id).csv") {
                magnetometer.append((row[0], station.latitude, station.longitude, row[1], row[2], row[3]))
            }
        }
        self.magnetometer = magnetometer
        clouds = try rows("clouds.csv").map { ($0[0], $0[1], $0[2], $0[3]) }
    }

    var cycles: [Date] {
        stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: 300)
            .map(Date.init(timeIntervalSince1970:))
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let query = item("storedquery_id"), let start = item("starttime"), let end = item("endtime") else {
            return (Data(), 400)
        }
        var xml = #"<?xml version="1.0" encoding="UTF-8"?><wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0">"#
        if query == "fmi::observations::magnetometer::simple" {
            for (time, latitude, longitude, x, y, z) in magnetometer where time >= start && time <= end {
                for (name, value) in [("MAGNX_PT10S_AVG", x), ("MAGNY_PT10S_AVG", y), ("MAGNZ_PT10S_AVG", z)] {
                    xml += Self.member("\(latitude)", "\(longitude)", time, name, value)
                }
            }
        } else {
            for (time, latitude, longitude, octas) in clouds where time >= start && time <= end {
                xml += Self.member(latitude, longitude, time, "TotalCloudCover", octas)
            }
        }
        return (Data((xml + "</wfs:FeatureCollection>").utf8), 200)
    }

    private static func member(_ latitude: String, _ longitude: String, _ time: String, _ name: String, _ value: String) -> String {
        "<wfs:member><BsWfs:BsWfsElement gml:id=\"x\"><BsWfs:Location><gml:Point><gml:pos>\(latitude) \(longitude) </gml:pos>"
            + "</gml:Point></BsWfs:Location><BsWfs:Time>\(time)</BsWfs:Time><BsWfs:ParameterName>\(name)</BsWfs:ParameterName>"
            + "<BsWfs:ParameterValue>\(value.isEmpty ? "NaN" : value)</BsWfs:ParameterValue></BsWfs:BsWfsElement></wfs:member>\n"
    }
}
