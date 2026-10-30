import AuroraCore
import Foundation

/// Outlook scenarios for UI tests (`-uiTestOutlook <scenario>`, specs/003-aurora-outlook quickstart §3).
/// NOAA and forecast times follow the test clock.
enum UITestOutlookScenario: String {
    /// Strong activity under the full moon; run with `-uiTestTime 2026-11-24T21:00:00Z`.
    case moon
    /// Southward solar wind (Ey 9.75 mV/m, Likely in every band), Kp 3 and a G2 watch for the
    /// day, clear skies; run on a dark night, e.g. `-uiTestTime 2026-11-09T20:00:00Z`.
    case storm
    /// Northward solar wind, Kp 2, no watch.
    case quiet
    /// Every NOAA request fails with HTTP 500; FMI works.
    case noaaDown = "noaa-down"
    /// Midsummer: run with `-uiTestTime 2026-06-21T12:00:00Z`.
    case summer

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-uiTestOutlook"), index + 1 < arguments.count else { return nil }
        self.init(rawValue: arguments[index + 1])
    }

    /// Scenarios that need FMI's strong-activity stubs.
    var strongActivity: Bool { self == .moon }
}

/// Serves synthetic FMI responses for UI tests (`-uiTestStubs`), so tests never touch the network.
///
/// Every station reports a steady oscillation that gives R ≈ 100 (Possible at most stations), and
/// a few weather stations report light cloud. Times follow the request's time window. With
/// `strongActivity` the oscillation gives R ≈ 310, above every station's red threshold.
struct UITestHTTPClient: HTTPClient {
    var strongActivity = false
    var outlook: UITestOutlookScenario?
    var now: @Sendable () -> Date = { Date() }

    func get(_ url: URL) async throws -> (Data, Int) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if url.host == "services.swpc.noaa.gov" {
            return noaa(url.lastPathComponent)
        }
        if value("storedquery_id") == "fmi::forecast::edited::weather::scandinavia::point::simple" {
            return (Data(cloudForecast(positions: items.filter { $0.name == "latlon" }.compactMap(\.value)).utf8), 200)
        }
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
                let x = step.isMultiple(of: 2) ? 0.0 : (strongActivity ? 6.9 : 2.3)
                for (name, v) in [("MAGNX_PT10S_AVG", x), ("MAGNY_PT10S_AVG", 120.0), ("MAGNZ_PT10S_AVG", -40.0)] {
                    members += Self.member(station.latitude, station.longitude, Date(timeIntervalSince1970: time), name, v)
                }
                time += 10
                step += 1
            }
        }
        return Self.collection(members)
    }

    // MARK: NOAA and the FMI forecast (spec 003)

    /// Without an outlook scenario NOAA answers 400, like any URL the stubs do not know.
    private func noaa(_ product: String) -> (Data, Int) {
        guard let outlook else { return (Data(), 400) }
        if outlook == .noaaDown { return (Data("<html>500</html>".utf8), 500) }
        let now = now()
        switch product {
        case "propagated-solar-wind-1-hour.json":
            // About an hour of minutes, the newest observed 8 minutes ago, arriving 50 minutes later.
            let (bz, speed) = outlook == .storm ? (-15.0, 650.0) : (3.0, 350.0)
            var rows = [#"["time_tag","speed","density","bz","propagated_time_tag"]"#]
            for minute in stride(from: 60, through: 8, by: -1) {
                let observed = Self.minute(now - Double(minute) * 60)
                rows.append(#"["\#(Self.format(observed))",\#(speed),4.5,\#(bz),"\#(Self.format(observed + 50 * 60))"]"#)
            }
            return (Data(("[" + rows.joined(separator: ",") + "]").utf8), 200)
        case "noaa-planetary-k-index-forecast.json":
            let kp = outlook == .storm ? 3.0 : 2.0
            let start = (now.timeIntervalSince1970 / 10_800).rounded(.down) * 10_800 - 2 * 86_400
            let blocks = (0..<40).map { index in
                let time = Date(timeIntervalSince1970: start + Double(index) * 10_800)
                let kind = time < now ? "observed" : "predicted"
                return #"{"time_tag":"\#(Self.format(time).dropLast())","kp":\#(kp),"observed":"\#(kind)","noaa_scale":null}"#
            }
            return (Data(("[" + blocks.joined(separator: ",") + "]").utf8), 200)
        case "alerts.json":
            guard outlook == .storm else { return (Data("[]".utf8), 200) }
            return (Data(Self.watchAlerts(now: now).utf8), 200)
        default:
            return (Data(), 404)
        }
    }

    /// A G2 watch for the current UTC day, issued ten hours earlier.
    private static func watchAlerts(now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let issued = now - 10 * 3_600
        func day(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            return date.formatted(Date.FormatStyle(timeZone: .gmt).locale(Locale(identifier: "en_US_POSIX")).month(.abbreviated).day(.twoDigits))
        }
        let issueTime = issued.formatted(Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits) \(month: .abbreviated) \(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: calendar))
        let message = """
            Space Weather Message Code: WATA30\r\nSerial Number: 300\r\nIssue Time: \(issueTime) UTC\r\n\r\n\
            WATCH: Geomagnetic Storm Category G2 Predicted\nHighest Storm Level Predicted by Day:\n\
            \(day(0)):  G2 (Moderate)   \(day(1)):  None (Below G1)   \(day(2)):  None (Below G1)\n
            """
        let object: [[String: String]] = [["product_id": "A30F", "issue_datetime": format(issued), "message": message]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// 10% cloud cover every hour from a day back to three days ahead, at every requested position.
    private func cloudForecast(positions: [String]) -> String {
        let first = (now().timeIntervalSince1970 / 3_600).rounded(.down) * 3_600 - 86_400
        var members = ""
        for position in positions {
            let parts = position.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { continue }
            for hour in 0..<96 {
                members += Self.member(parts[0], parts[1], Date(timeIntervalSince1970: first + Double(hour) * 3_600), "TotalCloudCover", 10)
            }
        }
        return Self.collection(members)
    }

    private static func minute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    private func clouds(end: Date) -> String {
        let time = Date(timeIntervalSince1970: (end.timeIntervalSince1970 / 600).rounded(.down) * 600)
        let stations: [(Double, Double, Double)] = [
            (66.52, 25.70, 2), (60.18, 24.95, 5), (69.90, 27.00, 1), (64.93, 25.37, 3), (62.40, 25.67, 8),
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
