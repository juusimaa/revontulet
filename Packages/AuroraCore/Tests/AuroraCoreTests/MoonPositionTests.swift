import Foundation
import Testing
@testable import AuroraCore

@Suite("Moon position (research R4)")
struct MoonPositionTests {
    struct Reference: Decodable, Sendable, CustomTestStringConvertible {
        let station: String
        let latitude: Double
        let longitude: Double
        let time: String
        let altitude: Double
        let illuminatedFraction: Double

        var testDescription: String { "\(station) \(time)" }
    }

    /// JPL Horizons values recorded by tools/record-moon-reference.py.
    static let references: [Reference] = {
        guard let data = try? Fixtures.data("outlook/moon-reference.json") else { return [] }
        return (try? JSONDecoder().decode([Reference].self, from: data)) ?? []
    }()

    @Test func referenceCoversHorizonAndAllStations() {
        #expect(Self.references.count >= 20)
        #expect(Set(Self.references.map(\.station)) == ["KEV", "OUJ", "TAR"])
        #expect(Self.references.contains { abs($0.altitude) < 2 })
    }

    /// SC-002: within 1° in altitude and 0.02 in illuminated fraction.
    @Test(arguments: references)
    func matchesHorizons(_ reference: Reference) {
        let state = MoonPosition.state(
            latitude: reference.latitude, longitude: reference.longitude, at: utc(reference.time))

        #expect(abs(state.altitude - reference.altitude) <= 1, "altitude \(state.altitude) vs \(reference.altitude)")
        #expect(abs(state.illuminatedFraction - reference.illuminatedFraction) <= 0.02,
                "fraction \(state.illuminatedFraction) vs \(reference.illuminatedFraction)")
    }

    @Test(arguments: references)
    func brightMeansUpAndAtLeastHalfLit(_ reference: Reference) {
        let state = MoonPosition.state(
            latitude: reference.latitude, longitude: reference.longitude, at: utc(reference.time))

        #expect(state.isBright == (state.altitude > 0 && state.illuminatedFraction >= 0.5))
    }

    @Test(arguments: [
        ("2026-11-09T12:00:00Z", MoonPhase.new),
        ("2026-11-17T12:00:00Z", .firstQuarter),
        ("2026-11-24T12:00:00Z", .full),
        ("2026-12-01T12:00:00Z", .lastQuarter),
        ("2026-11-13T00:00:00Z", .waxingCrescent),
        ("2026-11-21T00:00:00Z", .waxingGibbous),
        ("2026-11-28T00:00:00Z", .waningGibbous),
        ("2026-12-05T00:00:00Z", .waningCrescent),
    ])
    func phaseNames(time: String, phase: MoonPhase) {
        #expect(MoonPosition.state(latitude: 64.511, longitude: 27.227, at: utc(time)).phase == phase)
    }

    @Test func phaseKeys() {
        #expect(MoonPhase.new.key == "moon.phase.new")
        #expect(MoonPhase.waningCrescent.key == "moon.phase.waningCrescent")
        #expect(MoonPhase.allCases.count == 8)
    }

    @Test func stateRoundTrips() throws {
        let state = MoonPosition.state(latitude: 64.511, longitude: 27.227, at: utc("2026-11-24T21:00:00Z"))
        #expect(try JSONDecoder().decode(MoonState.self, from: JSONEncoder().encode(state)) == state)
    }
}
