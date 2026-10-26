import Foundation
import Testing
@testable import AuroraCore

@Suite("Alert season")
struct AlertSeasonTests {
    let kevo = try! AlertZones.all().first { $0.id == "KEV" }!

    @Test(arguments: ["2026-06-20T12:00:00Z", "2026-06-25T00:00:00Z", "2026-06-28T18:00:00Z"])
    func noDarknessAtKevoInLateJune(start: String) {
        #expect(!AlertSeason.hasDarknessWithin24h(zone: kevo, from: utc(start)))
    }

    @Test(arguments: ["2026-11-03T08:00:00Z", "2026-11-20T12:00:00Z"])
    func darknessAtKevoInNovember(start: String) {
        #expect(AlertSeason.hasDarknessWithin24h(zone: kevo, from: utc(start)))
    }

    @Test func matchesSolarPositionAt15MinuteSteps() throws {
        let start = utc("2026-08-01T00:00:00Z")
        let expected = (0..<96).contains { step in
            SolarPosition.darkness(
                latitude: kevo.representativePosition.latitude, longitude: kevo.representativePosition.longitude,
                at: start.addingTimeInterval(Double(step) * 900)) != .tooLight
        }
        #expect(AlertSeason.hasDarknessWithin24h(zone: kevo, from: start) == expected)
    }
}
