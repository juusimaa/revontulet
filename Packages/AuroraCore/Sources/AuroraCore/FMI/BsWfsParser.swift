import Foundation

/// Errors from fetching or reading FMI open data.
public enum FMIError: Error, Equatable, Sendable {
    /// The service answered with an OGC `ExceptionReport`; the message joins its exception texts.
    case exceptionReport(String)
    /// The service answered with a non-200 HTTP status.
    case httpStatus(Int)
    /// The response is not a recognisable WFS feature collection.
    case malformedResponse
}

/// One `BsWfs:BsWfsElement`: a single parameter value at a position and time.
public struct BsWfsElement: Sendable, Hashable {
    public var coordinate: Coordinate
    public var time: Date
    public var parameter: String
    /// nil when FMI reports `NaN`.
    public var value: Double?
}

/// Reads FMI's "simple" WFS response format.
///
/// The format is flat and machine-generated, so this is a small byte scanner rather than a general
/// XML parser. That keeps the core free of `XMLParser`, whose availability on Android is uncertain.
public enum BsWfsParser {
    public static func parse(_ data: Data) throws -> [BsWfsElement] {
        let bytes = [UInt8](data)
        let head = bytes.prefix(2_000)

        if head.byteRange(of: Token.exceptionReport) != nil {
            throw FMIError.exceptionReport(exceptionTexts(bytes).joined(separator: " "))
        }
        guard head.byteRange(of: Token.featureCollection) != nil else {
            throw FMIError.malformedResponse
        }

        var elements: [BsWfsElement] = []
        var position = bytes.startIndex
        while let open = bytes[position...].byteRange(of: Token.elementOpen) {
            guard let close = bytes[open.upperBound...].byteRange(of: Token.elementClose) else {
                throw FMIError.malformedResponse
            }
            elements.append(try element(bytes[open.upperBound..<close.lowerBound]))
            position = close.upperBound
        }
        return elements
    }

    private static func element(_ body: ArraySlice<UInt8>) throws -> BsWfsElement {
        guard let pos = text(in: body, between: Token.posOpen, and: Token.posClose),
              let timeText = text(in: body, between: Token.timeOpen, and: Token.timeClose),
              let name = text(in: body, between: Token.nameOpen, and: Token.nameClose),
              let valueText = text(in: body, between: Token.valueOpen, and: Token.valueClose)
        else { throw FMIError.malformedResponse }

        let numbers = pos.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard numbers.count == 2, let time = UTCTime.parse(timeText) else {
            throw FMIError.malformedResponse
        }
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Double(trimmed).flatMap { $0.isNaN ? nil : $0 }

        return BsWfsElement(
            coordinate: Coordinate(latitude: numbers[0], longitude: numbers[1]),
            time: time,
            parameter: name.trimmingCharacters(in: .whitespacesAndNewlines),
            value: value
        )
    }

    private static func text(in body: ArraySlice<UInt8>, between open: [UInt8], and close: [UInt8]) -> String? {
        guard let start = body.byteRange(of: open),
              let end = body[start.upperBound...].byteRange(of: close)
        else { return nil }
        return String(decoding: body[start.upperBound..<end.lowerBound], as: UTF8.self)
    }

    /// Contents of every `<…ExceptionText>` element (with or without a namespace prefix).
    private static func exceptionTexts(_ bytes: [UInt8]) -> [String] {
        var texts: [String] = []
        var position = bytes.startIndex
        while let match = bytes[position...].byteRange(of: Token.exceptionText) {
            position = match.upperBound
            // Skip closing tags such as `</ows:ExceptionText>`.
            guard let tagStart = bytes[..<match.lowerBound].lastIndex(of: UInt8(ascii: "<")),
                  bytes[tagStart + 1] != UInt8(ascii: "/")
            else { continue }
            guard let end = bytes[position...].firstIndex(of: UInt8(ascii: "<")) else { break }
            texts.append(String(decoding: bytes[position..<end], as: UTF8.self))
        }
        return texts
    }

    private enum Token {
        static let exceptionReport = Array("ExceptionReport".utf8)
        static let exceptionText = Array("ExceptionText>".utf8)
        static let featureCollection = Array("FeatureCollection".utf8)
        static let elementOpen = Array("<BsWfs:BsWfsElement".utf8)
        static let elementClose = Array("</BsWfs:BsWfsElement>".utf8)
        static let posOpen = Array("<gml:pos>".utf8)
        static let posClose = Array("</gml:pos>".utf8)
        static let timeOpen = Array("<BsWfs:Time>".utf8)
        static let timeClose = Array("</BsWfs:Time>".utf8)
        static let nameOpen = Array("<BsWfs:ParameterName>".utf8)
        static let nameClose = Array("</BsWfs:ParameterName>".utf8)
        static let valueOpen = Array("<BsWfs:ParameterValue>".utf8)
        static let valueClose = Array("</BsWfs:ParameterValue>".utf8)
    }
}

extension ArraySlice<UInt8> {
    /// First occurrence of `pattern`, scanning for its first byte before comparing the rest.
    fileprivate func byteRange(of pattern: [UInt8]) -> Range<Int>? {
        guard let first = pattern.first, count >= pattern.count else { return nil }
        var index = startIndex
        let last = endIndex - pattern.count
        while index <= last {
            guard let candidate = self[index...last].firstIndex(of: first) else { return nil }
            if self[candidate..<candidate + pattern.count].elementsEqual(pattern) {
                return candidate..<candidate + pattern.count
            }
            index = candidate + 1
        }
        return nil
    }
}

extension Array<UInt8> {
    fileprivate func byteRange(of pattern: [UInt8]) -> Range<Int>? {
        self[...].byteRange(of: pattern)
    }
}
