import Foundation

public enum ReferenceDataError: Error, Equatable {
    case missingResource(String)
    case invalidThresholds(stationID: String)
}

/// Loads the reference data bundled with the package: magnetometer stations and municipalities.
public enum ReferenceData {
    public static func loadStations() throws -> [Station] {
        try decodeStations(resource("stations"))
    }

    public static func loadMunicipalities() throws -> [Municipality] {
        try decodeMunicipalities(resource("municipalities"))
    }

    static func decodeStations(_ data: Data) throws -> [Station] {
        let stations = try JSONDecoder().decode([Station].self, from: data)
        for station in stations where !(0 < station.yellowThreshold && station.yellowThreshold < station.redThreshold) {
            throw ReferenceDataError.invalidThresholds(stationID: station.id)
        }
        return stations
    }

    static func decodeMunicipalities(_ data: Data) throws -> [Municipality] {
        try JSONDecoder().decode(MunicipalityFile.self, from: data).municipalities.map(\.municipality)
    }

    private static func resource(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw ReferenceDataError.missingResource(name)
        }
        return try Data(contentsOf: url)
    }
}

// MARK: - File format of municipalities.json (written by tools/build-municipalities.py)

/// Coordinates in the file are `[lat, lon]` arrays; bboxes are `[minLat, minLon, maxLat, maxLon]`.
private struct MunicipalityFile: Decodable {
    struct Entry: Decodable {
        let code: String
        let nameFi: String
        let nameSv: String?
        let point: [Double]
        let bbox: [Double]
        let polygons: [PolygonEntry]

        var municipality: Municipality {
            Municipality(
                code: code,
                nameFi: nameFi,
                nameSv: nameSv,
                representativePoint: Coordinate(latitude: point[0], longitude: point[1]),
                boundingBox: BoundingBox(
                    minLatitude: bbox[0], minLongitude: bbox[1], maxLatitude: bbox[2], maxLongitude: bbox[3]),
                polygons: polygons.map(\.polygon)
            )
        }
    }

    struct PolygonEntry: Decodable {
        let outer: [[Double]]
        let holes: [[[Double]]]

        var polygon: Polygon {
            Polygon(outer: Self.ring(outer), holes: holes.map(Self.ring))
        }

        private static func ring(_ points: [[Double]]) -> [Coordinate] {
            points.map { Coordinate(latitude: $0[0], longitude: $0[1]) }
        }
    }

    let municipalities: [Entry]
}
