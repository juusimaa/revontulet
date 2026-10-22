import AuroraCore
import Foundation

/// Serves synthetic FMI responses for UI tests (`-uiTestStubs`), so tests never touch the network.
///
/// Every station reports a steady oscillation that gives R ≈ 100 (Possible at most stations), and
/// a few weather stations report light cloud. Times follow the request's time window.
struct UITestHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let start = value("starttime").flatMap(Self.parse), let end = value("endtime").flatMap(Self.parse) else {
            return (Data(), 400)
        }
        switch value("storedquery_id") {
        case "fmi::observations::magnetometer::simple":
            return (Data(try magnetometer(start: start, end: end).utf8), 200)
        case "fmi::observations::weather::simple":
            return (Data(clouds(end: end).utf8), 200)
        default:
            return (Data(), 400)
        }
    }

    private func magnetometer(start: Date, end: Date) throws -> String {
        var members = ""
        // Like the live service, the newest sample is about a minute old.
        let first = (start.timeIntervalSince1970 / 10).rounded(.up) * 10
        let last = end.timeIntervalSince1970 - 60
        for station in try ReferenceData.loadStations() {
            var time = first
            var step = 0
            while time <= last {
                let x = step.isMultiple(of: 2) ? 0.0 : 2.3
                for (name, v) in [("MAGNX_PT10S_AVG", x), ("MAGNY_PT10S_AVG", 120.0), ("MAGNZ_PT10S_AVG", -40.0)] {
                    members += Self.member(station.latitude, station.longitude, Date(timeIntervalSince1970: time), name, v)
                }
                time += 10
                step += 1
            }
        }
        return Self.collection(members)
    }

    private func clouds(end: Date) -> String {
        let time = Date(timeIntervalSince1970: (end.timeIntervalSince1970 / 600).rounded(.down) * 600)
        let stations: [(Double, Double, Double)] = [
            (66.52, 25.70, 2), (60.18, 24.95, 5), (69.90, 27.00, 1), (65.01, 25.47, 3), (62.40, 25.67, 8),
        ]
        return Self.collection(stations.map { Self.member($0.0, $0.1, time, "TotalCloudCover", $0.2) }.joined())
    }

    private static func member(_ lat: Double, _ lon: Double, _ time: Date, _ name: String, _ value: Double) -> String {
        """
        <wfs:member><BsWfs:BsWfsElement gml:id="s"><BsWfs:Location><gml:Point><gml:pos>\(lat) \(lon) </gml:pos>\
        </gml:Point></BsWfs:Location><BsWfs:Time>\(format(time))</BsWfs:Time><BsWfs:ParameterName>\(name)\
        </BsWfs:ParameterName><BsWfs:ParameterValue>\(value)</BsWfs:ParameterValue></BsWfs:BsWfsElement></wfs:member>

        """
    }

    private static func collection(_ members: String) -> String {
        #"<?xml version="1.0" encoding="UTF-8"?><wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0">"#
            + "\n" + members + "</wfs:FeatureCollection>\n"
    }

    private static func parse(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    private static func format(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

/// Fails every request as if the device had no connection (`-uiTestOffline`).
struct OfflineHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) {
        throw URLError(.notConnectedToInternet)
    }
}
