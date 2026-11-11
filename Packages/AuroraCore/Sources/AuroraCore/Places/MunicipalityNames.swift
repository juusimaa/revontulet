import Foundation

/// A municipality's code, names and representative point, without its boundary polygons.
public struct MunicipalityName: Sendable, Hashable {
    public var code: String
    public var nameFi: String
    public var nameSv: String?
    public var representativePoint: Coordinate

    public init(code: String, nameFi: String, nameSv: String?, representativePoint: Coordinate) {
        self.code = code
        self.nameFi = nameFi
        self.nameSv = nameSv
        self.representativePoint = representativePoint
    }

    public func displayName(preferSwedish: Bool) -> String {
        if preferSwedish, let nameSv, !nameSv.isEmpty { return nameSv }
        return nameFi
    }
}

/// Cheap name lookup for widgets: decodes only code, names and point from the bundled data, never the
/// polygons.
public enum MunicipalityNames {
    public static func lookup(code: String) throws -> MunicipalityName? {
        guard let url = Bundle.module.url(forResource: "municipalities", withExtension: "json") else {
            throw ReferenceDataError.missingResource("municipalities")
        }
        return try lookup(code: code, in: Data(contentsOf: url))
    }

    static func lookup(code: String, in data: Data) throws -> MunicipalityName? {
        try JSONDecoder().decode(File.self, from: data).municipalities
            .first { $0.code == code }
            .map {
                MunicipalityName(
                    code: $0.code, nameFi: $0.nameFi, nameSv: $0.nameSv,
                    representativePoint: Coordinate(latitude: $0.point[0], longitude: $0.point[1]))
            }
    }

    /// Mirrors municipalities.json but declares no bbox or polygon fields, so those are skipped.
    struct File: Decodable {
        struct Entry: Decodable {
            let code: String
            let nameFi: String
            let nameSv: String?
            let point: [Double]
        }

        let municipalities: [Entry]
    }
}
