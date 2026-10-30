import Foundation
import Testing
@testable import AuroraCore

@Suite("AuroraResult coding")
struct AuroraResultCodingTests {
    private static let station = Station(
        id: "KEV", name: "Kevo", latitude: 69.761, longitude: 27.01, yellowThreshold: 55, redThreshold: 165)

    static let results: [AuroraResult] = [
        AuroraResult(
            place: Place(coordinate: Coordinate(latitude: 69.9078, longitude: 27.0265),
                         municipalityCode: "890", source: .manual),
            chance: Chance(level: .high, limitingFactor: nil, cloudsIncluded: true),
            reading: StationReading(station: station, r: 182.37, measuredAt: utc("2026-10-22T16:35:20Z"),
                                    activity: .probable),
            distanceToStationKm: 16.4,
            usedMoreDistantStation: false,
            darkness: .dark,
            clouds: CloudCover(condition: .clear, octas: 1, source: Coordinate(latitude: 69.75, longitude: 27.03),
                               distanceKm: 17.2),
            moon: MoonState(altitude: 12.5, illuminatedFraction: 0.83, phase: .waxingGibbous, isBright: true),
            computedAt: utc("2026-10-22T16:35:30Z")),
        AuroraResult(
            place: Place(coordinate: Coordinate(latitude: 60.1699, longitude: 24.9384),
                         municipalityCode: "091", source: .currentLocation),
            chance: Chance(level: .none, limitingFactor: .light, cloudsIncluded: false),
            reading: StationReading(station: station, r: nil, measuredAt: utc("2026-06-21T09:00:00Z"), activity: nil),
            distanceToStationKm: 1061.9,
            usedMoreDistantStation: true,
            darkness: .tooLight,
            clouds: .unknown,
            moon: MoonState(altitude: -20.1, illuminatedFraction: 0.32, phase: .waningCrescent, isBright: false),
            computedAt: utc("2026-06-21T09:00:12Z")),
    ]

    @Test(arguments: results)
    func roundTrip(_ result: AuroraResult) throws {
        let data = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(AuroraResult.self, from: data) == result)
    }

    /// A result cached by 2.0 has no moon; it does not decode, so the cache counts as empty.
    @Test func versionOneResultWithoutMoonFailsToDecode() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AuroraResult.self, from: Self.versionOneData(Self.results[0]))
        }
    }

    static func versionOneData(_ result: AuroraResult) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        object["moon"] = nil
        return try JSONSerialization.data(withJSONObject: object)
    }
}
