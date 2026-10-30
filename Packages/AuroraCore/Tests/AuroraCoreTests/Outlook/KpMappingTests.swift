import Foundation
import Testing
@testable import AuroraCore

/// The Kp mapping applied to the Kp that was actually observed agrees with the highest FMI level
/// of the night at the zone's station (SC-004, research R7). Station-nights written by
/// tools/calibrate-kp.py from GFZ definitive Kp and FMI magnetometer archives.
@Suite("Kp mapping against recorded nights (SC-004)")
struct KpMappingTests {
    struct StationNight: Decodable, Sendable {
        let night: String
        let zone: String
        let band: Band
        let kp: Double
        let fmi: ActivityLevel
    }

    static let stationNights: [StationNight] =
        (try? JSONDecoder().decode([StationNight].self, from: Fixtures.data("outlook/kp-nights.json"))) ?? []

    @Test func atLeast80PercentAgreeOverAtLeast30Nights() {
        let agree = Self.stationNights.filter { OutlookCalculator.activity(kp: $0.kp, band: $0.band) == $0.fmi }.count

        #expect(Set(Self.stationNights.map(\.night)).count >= 30)
        #expect(Set(Self.stationNights.map(\.band)) == Set(Band.allCases))
        #expect(Double(agree) >= 0.8 * Double(Self.stationNights.count), "\(agree) of \(Self.stationNights.count)")
    }

    @Test func zonesAreInTheirBands() {
        for night in Self.stationNights {
            #expect(Band.of(zoneID: night.zone) == night.band, "\(night.night) \(night.zone)")
        }
    }
}
