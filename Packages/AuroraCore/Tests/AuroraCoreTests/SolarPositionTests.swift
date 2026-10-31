import Foundation
import Testing
@testable import AuroraCore

@Suite("Solar position")
struct SolarPositionTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let latitude: Double
        let longitude: Double
        let time: String
        /// Sun elevation in degrees from the NOAA solar calculator (geometric, no refraction).
        let elevation: Double

        var testDescription: String { name }
    }

    // Times are local solar noon or midnight, so the reference elevation is the culmination
    // (90° − latitude + declination, or latitude + declination − 90°).
    static let cases: [Case] = [
        Case(name: "Helsinki, summer solstice noon", latitude: 60.1699, longitude: 24.9384,
             time: "2026-06-21T10:22:00Z", elevation: 53.27),
        Case(name: "Helsinki, winter solstice noon", latitude: 60.1699, longitude: 24.9384,
             time: "2026-12-21T10:18:00Z", elevation: 6.40),
        Case(name: "Helsinki, winter solstice midnight", latitude: 60.1699, longitude: 24.9384,
             time: "2026-12-20T22:18:00Z", elevation: -53.27),
        Case(name: "Helsinki, March equinox noon", latitude: 60.1699, longitude: 24.9384,
             time: "2026-03-20T10:28:00Z", elevation: 29.76),
        Case(name: "Utsjoki, summer solstice midnight", latitude: 69.9078, longitude: 27.0265,
             time: "2026-06-20T22:14:00Z", elevation: 3.34),
        Case(name: "Utsjoki, winter solstice noon", latitude: 69.9078, longitude: 27.0265,
             time: "2026-12-21T10:10:00Z", elevation: -3.35),
    ]

    @Test(arguments: cases)
    func elevationMatchesNOAA(_ reference: Case) {
        let elevation = SolarPosition.elevation(
            latitude: reference.latitude, longitude: reference.longitude, at: utc(reference.time))
        #expect(abs(elevation - reference.elevation) <= 0.5, "\(elevation)")
    }

    @Test(arguments: [
        (10.0, Darkness.tooLight),
        (-5.99, .tooLight),
        (-6, .twilight),
        (-11.99, .twilight),
        (-12, .dark),
        (-40, .dark),
    ])
    func darknessBoundaries(elevation: Double, expected: Darkness) {
        #expect(SolarPosition.darkness(elevation: elevation) == expected)
    }

    @Test func darknessForAPlace() {
        // Utsjoki at midsummer midnight is light; Helsinki at winter midnight is dark.
        #expect(SolarPosition.darkness(latitude: 69.9078, longitude: 27.0265, at: utc("2026-06-20T22:14:00Z")) == .tooLight)
        #expect(SolarPosition.darkness(latitude: 60.1699, longitude: 24.9384, at: utc("2026-12-20T22:18:00Z")) == .dark)
    }

    @Test func nextDarknessOnAnAutumnAfternoon() throws {
        // Rovaniemi, 23 October: the sun sets around 14:00 UTC and is 6° down about 45 minutes later.
        let noon = utc("2026-10-23T10:00:00Z")
        let dark = try #require(SolarPosition.nextDarkness(latitude: 66.50, longitude: 25.73, after: noon))
        #expect(dark > utc("2026-10-23T14:00:00Z") && dark < utc("2026-10-23T15:30:00Z"), "\(dark)")
        #expect(SolarPosition.darkness(latitude: 66.50, longitude: 25.73, at: dark) != .tooLight)
        #expect(SolarPosition.darkness(latitude: 66.50, longitude: 25.73, at: dark.addingTimeInterval(-5 * 60)) == .tooLight)
    }

    @Test func darkNightsReturnAfterMidsummer() throws {
        // Oulu: the sun stays above −6° from late May until late July.
        let midsummer = utc("2026-06-21T12:00:00Z")
        let dark = try #require(SolarPosition.nextDarkNight(latitude: 65.01, longitude: 25.47, after: midsummer))
        #expect(dark > utc("2026-07-15T00:00:00Z") && dark < utc("2026-08-05T00:00:00Z"), "\(dark)")
        // No darkness in the day before it: it is the first dark night.
        #expect(SolarPosition.nextDarkness(latitude: 65.01, longitude: 25.47, after: dark.addingTimeInterval(-86_400)) == dark)
        // Within 24 hours it is the same as nextDarkness.
        let autumn = utc("2026-10-23T10:00:00Z")
        #expect(SolarPosition.nextDarkNight(latitude: 66.50, longitude: 25.73, after: autumn)
            == SolarPosition.nextDarkness(latitude: 66.50, longitude: 25.73, after: autumn))
    }

    @Test func noDarknessAtMidsummerInLapland() {
        #expect(SolarPosition.nextDarkness(latitude: 69.9078, longitude: 27.0265, after: utc("2026-06-20T12:00:00Z")) == nil)
    }
}
