import Foundation
import Synchronization
@testable import AuroraCore

/// A recorded alert night (`Fixtures/alerts/<YYYYMMDD>/`, T016).
struct RecordedNight: Sendable {
    struct ExpectedAlert: Codable, Hashable, Sendable {
        var zone: String
        var level: String
        var time: Date
    }

    let name: String
    let start: Date
    let end: Date
    /// Complete and incomplete samples per station, sorted by time.
    let magnetometer: [String: [MagnetometerSample]]
    /// (time, position, raw value) rows, sorted by time.
    let clouds: [(time: Date, coordinate: Coordinate, value: Double?)]
    let expected: [ExpectedAlert]

    static let names = ["20261014", "20261018", "20261019", "20261024"]

    private static let cache = Mutex<[String: RecordedNight]>([:])

    /// Loads a night once per test process.
    static func named(_ name: String) throws -> RecordedNight {
        if let night = cache.withLock({ $0[name] }) { return night }
        let night = try RecordedNight(name)
        cache.withLock { $0[name] = night }
        return night
    }

    private init(_ name: String) throws {
        self.name = name
        let folder = "alerts/\(name)/"
        struct Window: Decodable { var start: Date; var end: Date }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let window = try decoder.decode(Window.self, from: Fixtures.data(folder + "night.json"))
        start = window.start
        end = window.end
        expected = try decoder.decode([ExpectedAlert].self, from: Fixtures.data(folder + "expected.json"))

        var magnetometer: [String: [MagnetometerSample]] = [:]
        for station in try ReferenceData.loadStations() {
            let file = folder + "magnetometer-\(station.id).csv"
            guard Fixtures.exists(file) else { continue }
            magnetometer[station.id] = try Self.samples(csv: Fixtures.data(file), stationID: station.id)
        }
        self.magnetometer = magnetometer

        clouds = String(decoding: try Fixtures.data(folder + "clouds.csv"), as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("time") }
            .map { line in
                let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                return (UTCTime.parse(fields[0])!, Coordinate(latitude: Double(fields[1])!, longitude: Double(fields[2])!), Double(fields[3]))
            }
    }

    /// Like `MagnetometerFixtures.samples`, with the core's fast fixed-format time parser.
    private static func samples(csv data: Data, stationID: String) -> [MagnetometerSample] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("time") }
            .map { line in
                let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                return MagnetometerSample(stationID: stationID, time: UTCTime.parse(fields[0].utf8)!,
                                          x: Double(fields[1]), y: Double(fields[2]), z: Double(fields[3]))
            }
    }

    /// Evaluation cycle times: every 5 minutes from the start to the end of the night.
    var cycles: [Date] {
        stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: 300)
            .map(Date.init(timeIntervalSince1970:))
    }
}

/// Answers FMI requests from a recorded night, building each response for the request's own
/// time window, the way FMI would have answered at that time.
///
/// With `shift`, the night is replayed that much later: requests and response times are moved by
/// it, so the same activity and clouds can be evaluated under another sky (e.g. a full moon).
final class NightReplayHTTPClient: HTTPClient {
    static let magnetometerQuery = "fmi::observations::magnetometer::simple"
    static let cloudsQuery = "fmi::observations::weather::simple"

    private let night: RecordedNight
    private let shift: TimeInterval
    private let stations: [String: Station]
    private let state = Mutex<(requested: [URL], failing: Set<String>, droppedStations: Set<String>)>(([], [], []))

    init(_ night: RecordedNight, shift: TimeInterval = 0) throws {
        self.night = night
        self.shift = shift
        stations = Dictionary(uniqueKeysWithValues: try ReferenceData.loadStations().map { ($0.id, $0) })
    }

    /// Makes requests for the stored query fail (e.g. FMI unreachable).
    func setFailing(_ query: String, _ failing: Bool) {
        state.withLock { state in
            if failing { state.failing.insert(query) } else { state.failing.remove(query) }
        }
    }

    /// Leaves these stations out of magnetometer responses (station outage).
    func dropStations(_ ids: Set<String>) {
        state.withLock { $0.droppedStations = ids }
    }

    var requestedURLs: [URL] { state.withLock { $0.requested } }

    func requests(for query: String) -> [URL] {
        requestedURLs.filter { Self.item("storedquery_id", in: $0) == query }
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        let query = Self.item("storedquery_id", in: url) ?? ""
        let (failing, dropped) = state.withLock { state in
            state.requested.append(url)
            return (state.failing.contains(query), state.droppedStations)
        }
        if failing { throw StubHTTPClient.StubError() }
        guard let start = Self.item("starttime", in: url).map(utc)?.addingTimeInterval(-shift),
              let end = Self.item("endtime", in: url).map(utc)?.addingTimeInterval(-shift)
        else {
            return (Data(), 400)
        }
        switch query {
        case Self.magnetometerQuery: return (magnetometerResponse(start: start, end: end, dropped: dropped), 200)
        case Self.cloudsQuery: return (cloudsResponse(start: start, end: end), 200)
        default: return (Data(), 400)
        }
    }

    private func magnetometerResponse(start: Date, end: Date, dropped: Set<String>) -> Data {
        var xml = Self.header
        for (stationID, samples) in night.magnetometer.sorted(by: { $0.key < $1.key }) where !dropped.contains(stationID) {
            guard let station = stations[stationID] else { continue }
            for sample in samples where sample.time >= start && sample.time <= end {
                for (name, value) in [("MAGNX_PT10S_AVG", sample.x), ("MAGNY_PT10S_AVG", sample.y), ("MAGNZ_PT10S_AVG", sample.z)] {
                    xml += Self.member(station.coordinate, sample.time.addingTimeInterval(shift), name, value)
                }
            }
        }
        return Data((xml + Self.footer).utf8)
    }

    private func cloudsResponse(start: Date, end: Date) -> Data {
        var xml = Self.header
        for row in night.clouds where row.time >= start && row.time <= end {
            xml += Self.member(row.coordinate, row.time.addingTimeInterval(shift), "TotalCloudCover", row.value)
        }
        return Data((xml + Self.footer).utf8)
    }

    private static let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0">

        """
    private static let footer = "</wfs:FeatureCollection>\n"

    private static func member(_ coordinate: Coordinate, _ time: Date, _ name: String, _ value: Double?) -> String {
        """
        <wfs:member><BsWfs:BsWfsElement gml:id="x">\
        <BsWfs:Location><gml:Point><gml:pos>\(coordinate.latitude) \(coordinate.longitude) </gml:pos></gml:Point></BsWfs:Location>\
        <BsWfs:Time>\(UTCTime.format(time))</BsWfs:Time>\
        <BsWfs:ParameterName>\(name)</BsWfs:ParameterName>\
        <BsWfs:ParameterValue>\(value.map { String($0) } ?? "NaN")</BsWfs:ParameterValue>\
        </BsWfs:BsWfsElement></wfs:member>

        """
    }

    private static func item(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
