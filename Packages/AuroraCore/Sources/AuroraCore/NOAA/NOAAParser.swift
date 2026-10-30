import Foundation

/// Errors from fetching or reading NOAA SWPC products.
public enum NOAAError: Error, Equatable, Sendable {
    /// The service answered with a non-200 HTTP status.
    case httpStatus(Int)
    /// The body is not the product's JSON shape.
    case malformedResponse
}

/// Reads NOAA SWPC products (contracts/noaa-data.md). SWPC changes products without notice, so
/// columns are found by name and values may be numbers or numeric strings.
enum NOAAParser {
    /// Propagated solar wind: an array of arrays whose first row is the header. Rows without a
    /// time are dropped, a repeated minute keeps its last row, and the result is sorted by time.
    static func propagatedSolarWind(_ data: Data) throws -> [SolarWindSample] {
        guard case .array(let rows)? = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let header)? = rows.first
        else { throw NOAAError.malformedResponse }
        let names = header.map { $0.string ?? "" }
        guard let time = names.firstIndex(of: "time_tag"), let bz = names.firstIndex(of: "bz"),
              let speed = names.firstIndex(of: "speed"), let arrival = names.firstIndex(of: "propagated_time_tag")
        else { throw NOAAError.malformedResponse }
        let density = names.firstIndex(of: "density")

        var byTime: [Date: SolarWindSample] = [:]
        for case .array(let row) in rows.dropFirst() {
            func cell(_ index: Int?) -> JSONValue? { index.flatMap { $0 < row.count ? row[$0] : nil } }
            guard let observed = cell(time)?.string.flatMap(NOAATime.parse) else { continue }
            byTime[observed] = SolarWindSample(
                time: observed, arrival: cell(arrival)?.string.flatMap(NOAATime.parse),
                bz: cell(bz)?.number, speed: cell(speed)?.number, density: cell(density)?.number)
        }
        return byTime.values.sorted { $0.time < $1.time }
    }

    /// Kp forecast: an array of objects, or SWPC's earlier array of arrays with a header row.
    /// Times without a zone are UTC; an unknown `observed` value counts as predicted.
    static func kpForecast(_ data: Data, fetchedAt: Date) throws -> KpForecast {
        guard case .array(let rows)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw NOAAError.malformedResponse
        }
        var records: [[String: JSONValue]] = []
        if case .array(let header)? = rows.first {
            let names = header.map { $0.string ?? "" }
            for case .array(let row) in rows.dropFirst() {
                records.append(Dictionary(zip(names, row), uniquingKeysWith: { first, _ in first }))
            }
        } else {
            for case .object(let object) in rows { records.append(object) }
        }
        let blocks = records.compactMap { record -> KpBlock? in
            guard let start = record["time_tag"]?.string.flatMap(NOAATime.parse), let kp = record["kp"]?.number else {
                return nil
            }
            return KpBlock(start: start, kp: kp, kind: record["observed"]?.string.flatMap(KpKind.init(rawValue:)) ?? .predicted)
        }
        guard !blocks.isEmpty else { throw NOAAError.malformedResponse }
        return KpForecast(blocks: blocks, fetchedAt: fetchedAt)
    }

    /// Geomagnetic storm watches in effect at `now`, from the alerts product
    /// (contracts/noaa-data.md, Storm watches, steps 1–5). Messages issued after `now` are left
    /// out. A watch message that matches no pattern is skipped without failing the file.
    static func stormWatches(_ data: Data, now: Date) throws -> [StormWatch] {
        guard case .array(let messages)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw NOAAError.malformedResponse
        }
        var parsed: [WatchMessage] = []
        for case .object(let object) in messages {
            guard let text = object["message"]?.string, text.contains(Patterns.watchCode),
                  let message = WatchMessage(text, issueDatetime: object["issue_datetime"]?.string),
                  message.issuedAt <= now
            else { continue }
            parsed.append(message)
        }
        parsed.sort { $0.issuedAt < $1.issuedAt }

        // The newest watch supersedes all earlier ones; later cancellations apply on top of it.
        guard let newest = parsed.last(where: { !$0.isCancellation }) else { return [] }
        var levels = newest.days
        for cancellation in parsed where cancellation.isCancellation && cancellation.issuedAt > newest.issuedAt {
            levels.merge(cancellation.days) { _, new in new }
        }
        let today = UTCTime.format(now).prefix(10)
        var byLevel: [Int: [String]] = [:]
        for (day, level) in levels where level > 0 && day >= today {
            byLevel[level, default: []].append(day)
        }
        return byLevel.keys.sorted().map { StormWatch(level: $0, days: byLevel[$0]!.sorted(), issuedAt: newest.issuedAt) }
    }

    private enum Patterns {
        nonisolated(unsafe) static let watchCode = #/Space Weather Message Code: WATA\d\d/#
        nonisolated(unsafe) static let issueTime = #/Issue Time: (\d{4}) ([A-Z][a-z]{2}) (\d{1,2}) (\d{2})(\d{2}) UTC/#
        nonisolated(unsafe) static let dayLevel = #/([A-Z][a-z]{2}) ?(\d{1,2}) *: *(G[1-5]|None)/#
    }

    /// One WATA message: a watch or a cancellation with its G level per UTC day (0 = None).
    private struct WatchMessage {
        var issuedAt: Date
        var isCancellation: Bool
        var days: [String: Int]

        init?(_ text: String, issueDatetime: String?) {
            let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let match = text.firstMatch(of: Patterns.issueTime),
               let month = Self.month(match.2), let day = Int(match.3) {
                issuedAt = UTCTime.parse("\(match.1)-\(Self.pad(month))-\(Self.pad(day))T\(match.4):\(match.5):00Z") ?? .distantPast
            } else if let fallback = issueDatetime.flatMap(NOAATime.parse) {
                issuedAt = fallback
            } else {
                return nil
            }
            guard issuedAt != .distantPast else { return nil }
            if lines.contains(where: { $0.hasPrefix("CANCEL WATCH:") }) {
                isCancellation = true
            } else if lines.contains(where: { $0.hasPrefix("WATCH:") }) {
                isCancellation = false
            } else {
                return nil
            }

            // Day lines follow the header line, up to the next empty line.
            guard let header = lines.firstIndex(where: {
                $0.hasPrefix("Highest Storm Level Predicted by Day:") || $0.hasPrefix("Cancelled Level Predicted:")
            }) else { return nil }
            let dayLines = lines[(header + 1)...].prefix { !$0.isEmpty }.joined(separator: " ")
            let issueYear = Int(UTCTime.format(issuedAt).prefix(4))!
            let issueMonth = Int(UTCTime.format(issuedAt).dropFirst(5).prefix(2))!
            var days: [String: Int] = [:]
            for match in dayLines.matches(of: Patterns.dayLevel) {
                guard let month = Self.month(match.1), let day = Int(match.2) else { continue }
                // Days have no year: December's watch can cover January.
                let year = month < issueMonth - 6 ? issueYear + 1 : issueYear
                days["\(year)-\(Self.pad(month))-\(Self.pad(day))"] = match.3 == "None" ? 0 : Int(match.3.dropFirst())!
            }
            guard !days.isEmpty else { return nil }
            self.days = days
        }

        private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

        private static func month(_ name: Substring) -> Int? {
            months.firstIndex(of: String(name)).map { $0 + 1 }
        }

        private static func pad(_ value: Int) -> String {
            value < 10 ? "0\(value)" : "\(value)"
        }
    }
}

/// SWPC timestamps: `2026-10-30T09:32:00Z`, `2026-10-27T00:00:00` (UTC without zone) or
/// `2026-10-20 19:12:44.190`.
enum NOAATime {
    static func parse(_ text: String) -> Date? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("Z") { trimmed.removeLast() }
        guard trimmed.count >= 19 else { return nil }
        let seconds = String(trimmed.prefix(19)).replacingOccurrences(of: " ", with: "T")
        return UTCTime.parse(seconds + "Z")
    }
}

/// Any JSON value, for decoding products whose shape may change.
enum JSONValue: Decodable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// A number, or a string holding one; NaN and fill values are nil.
    var number: Double? {
        let value: Double? = switch self {
        case .number(let value): value
        case .string(let text): Double(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }
}
