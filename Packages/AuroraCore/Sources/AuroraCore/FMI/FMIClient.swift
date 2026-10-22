import Foundation

/// Fetches and decodes FMI open data for the app.
public struct FMIClient: Sendable {
    /// How close (in degrees) a reported position must be to a bundled station to count as that station.
    static let stationMatchTolerance = 0.01

    private let http: any HTTPClient
    private let stations: [Station]

    public init(http: any HTTPClient, stations: [Station]) {
        self.http = http
        self.stations = stations
    }

    /// Magnetometer samples for the bundled stations, sorted by station and time.
    /// Positions that match no bundled station are ignored.
    public func magnetometerSamples(now: Date) async throws -> [MagnetometerSample] {
        let elements = try await fetch(FMIRequests.magnetometer(now: now))

        struct Key: Hashable { let stationID: String; let time: Date }
        var samples: [Key: MagnetometerSample] = [:]
        var stationByCoordinate: [Coordinate: Station?] = [:]

        for element in elements {
            let station: Station? = stationByCoordinate[element.coordinate] ?? {
                let match = stations.first {
                    abs($0.latitude - element.coordinate.latitude) <= Self.stationMatchTolerance
                        && abs($0.longitude - element.coordinate.longitude) <= Self.stationMatchTolerance
                }
                stationByCoordinate[element.coordinate] = match
                return match
            }()
            guard let station else { continue }

            let key = Key(stationID: station.id, time: element.time)
            var sample = samples[key]
                ?? MagnetometerSample(stationID: station.id, time: element.time, x: nil, y: nil, z: nil)
            switch element.parameter {
            case "MAGNX_PT10S_AVG": sample.x = element.value
            case "MAGNY_PT10S_AVG": sample.y = element.value
            case "MAGNZ_PT10S_AVG": sample.z = element.value
            default: continue
            }
            samples[key] = sample
        }
        return samples.values.sorted { ($0.stationID, $0.time) < ($1.stationID, $1.time) }
    }

    /// The latest cloud cover per weather station position.
    public func cloudObservations(now: Date) async throws -> [CloudObservation] {
        let elements = try await fetch(FMIRequests.clouds(now: now))

        var latest: [Coordinate: CloudObservation] = [:]
        for element in elements where element.parameter == "TotalCloudCover" {
            if let existing = latest[element.coordinate], existing.time >= element.time { continue }
            latest[element.coordinate] = CloudObservation(
                coordinate: element.coordinate, time: element.time, octas: Self.octas(element.value))
        }
        return latest.values.sorted {
            ($0.coordinate.latitude, $0.coordinate.longitude) < ($1.coordinate.latitude, $1.coordinate.longitude)
        }
    }

    /// 0–8 octas; 9 (sky obscured) and missing values are unknown.
    static func octas(_ value: Double?) -> Int? {
        guard let value, value >= 0, value <= 8 else { return nil }
        return Int(value.rounded())
    }

    private func fetch(_ url: URL) async throws -> [BsWfsElement] {
        let (data, status) = try await http.get(url)
        guard status == 200 else { throw FMIError.httpStatus(status) }
        return try BsWfsParser.parse(data)
    }
}
