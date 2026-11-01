import Foundation
import Testing
@testable import AuroraCore

@Suite("Alert message")
struct AlertMessageTests {
    private func decision(_ level: ChanceLevel, _ reason: ChanceReason, cloudsIncluded: Bool) -> AlertDecision {
        let condition = ZoneCondition(
            zoneID: "OUJ", chance: Chance(level: level, limitingFactor: nil, cloudsIncluded: cloudsIncluded),
            reason: reason, activityStationID: "OUJ", dataTime: utc("2026-11-03T20:00:00Z"))
        return AlertDecision(zoneID: "OUJ", level: level, condition: condition)
    }

    /// contracts/push-notification.md, Keys, and chance-rules v2 alert keys.
    static let table: [(ChanceLevel, ChanceReason, Bool, String)] = [
        (.high, .goodConditions, true, "alert.body.goodConditions"),
        (.high, .goodConditions, false, "alert.body.goodConditions.cloudsUnknown"),
        (.moderate, .someActivity, true, "alert.body.someActivity"),
        (.moderate, .someActivity, false, "alert.body.someActivity.cloudsUnknown"),
        (.moderate, .twilight, true, "alert.body.twilight"),
        (.moderate, .twilight, false, "alert.body.twilight.cloudsUnknown"),
        (.moderate, .partlyCloudy, true, "alert.body.partlyCloudy"),
        (.moderate, .brightMoon, true, "alert.body.brightMoon"),
        (.moderate, .brightMoon, false, "alert.body.brightMoon.cloudsUnknown"),
    ]

    /// Without `moonKeys` (2.0 has no moon text, research R9) the moon case gets the twilight text.
    static func withoutMoonKeys(_ key: String) -> String {
        key.replacingOccurrences(of: "alert.body.brightMoon", with: "alert.body.twilight")
    }

    @Test(arguments: [true, false])
    func keysPerLevelReasonAndClouds(moonKeys: Bool) {
        for (level, reason, clouds, body) in Self.table {
            let message = AlertMessage.make(for: decision(level, reason, cloudsIncluded: clouds), moonKeys: moonKeys)
            #expect(message.bodyKey == (moonKeys ? body : Self.withoutMoonKeys(body)), "\(level) \(reason) clouds known: \(clouds)")
            #expect(message.titleKey == (level == .high ? "alert.title.high" : "alert.title.moderate"))
            #expect(message.arguments == ["Oulujärvi"])
        }
    }

    @Test func moonCaseWithAndWithoutMoonKeys() {
        let known = decision(.moderate, .brightMoon, cloudsIncluded: true)
        let unknown = decision(.moderate, .brightMoon, cloudsIncluded: false)

        #expect(AlertMessage.make(for: known, moonKeys: true).bodyKey == "alert.body.brightMoon")
        #expect(AlertMessage.make(for: unknown, moonKeys: true).bodyKey == "alert.body.brightMoon.cloudsUnknown")
        #expect(AlertMessage.make(for: known, moonKeys: false).bodyKey == "alert.body.twilight")
        #expect(AlertMessage.make(for: unknown, moonKeys: false).bodyKey == "alert.body.twilight.cloudsUnknown")
    }

    /// Every (activity, darkness, moon, clouds) combination the chance rules turn into Moderate or
    /// High is in the table, so no reachable alert lacks text.
    @Test func everyReachableCombinationIsCovered() {
        var reachable: Set<String> = []
        for activity in ActivityLevel.allCases {
            for darkness in Darkness.allCases {
                for moonBright in [false, true] {
                    for clouds in CloudCondition.allCases {
                        let chance = ChanceCalculator.chance(
                            activity: activity, darkness: darkness, moonBright: moonBright, clouds: clouds)
                        guard chance.level >= .moderate else { continue }
                        let reason = ChanceCalculator.reason(for: chance, activity: activity, clouds: clouds)
                        let row = Self.table.first { $0.0 == chance.level && $0.1 == reason && $0.2 == chance.cloudsIncluded }
                        #expect(row != nil, "\(activity) \(darkness) \(moonBright) \(clouds) → \(chance.level) \(reason)")
                        reachable.insert(row?.3 ?? "")
                    }
                }
            }
        }
        #expect(reachable == Set(Self.table.map(\.3)))
    }

    @Test func stationNameIsTheOnlyArgument() {
        let condition = ZoneCondition(
            zoneID: "OUJ", chance: Chance(level: .high, limitingFactor: nil, cloudsIncluded: true),
            reason: .goodConditions, activityStationID: "RAN", dataTime: .now)
        let message = AlertMessage.make(for: AlertDecision(zoneID: "TAR", level: .high, condition: condition), moonKeys: true)

        // Named after the zone's own station, even when another station's reading was used.
        #expect(message.arguments == ["Tartu"])
    }

    @Test func testMessage() {
        #expect(AlertMessage.test == AlertMessage(titleKey: "alert.title.test", bodyKey: "alert.body.test", arguments: []))
    }

    @Test func allKeysListsExactlyTheThirteenKeys() {
        let expected: Set<String> = Set(Self.table.map(\.3)).union([
            "alert.title.high", "alert.title.moderate", "alert.title.test", "alert.body.test",
        ])
        #expect(AlertMessage.allKeys.count == 13)
        #expect(Set(AlertMessage.allKeys) == expected)
    }

    @Test func titleAndBodyKeysAreSplit() {
        #expect(AlertMessage.titleKeys.count == 3)
        #expect(AlertMessage.bodyKeys.count == 10)
        #expect(Set(AlertMessage.titleKeys + AlertMessage.bodyKeys) == Set(AlertMessage.allKeys))
    }
}
