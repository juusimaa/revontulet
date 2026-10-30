import Foundation
import Testing
@testable import AuroraCore

/// contracts/alert-rules.md §2: reference cases 1–16 and synthetic nights (SC-002, SC-003).
@Suite("Alert policy")
struct AlertPolicyTests {
    /// 2026-11-03 22:00 in Helsinki (EET, UTC+2).
    static let evening = utc("2026-11-03T20:00:00Z")

    static func at(_ minutes: Int, from base: Date = evening) -> Date {
        base.addingTimeInterval(Double(minutes) * 60)
    }

    /// A condition for zone OUJ at `level`, with data `age` minutes old.
    static func condition(_ level: ChanceLevel, at now: Date, ageMinutes: Double = 1,
                          reason: ChanceReason? = nil, cloudsIncluded: Bool = true, station: String = "OUJ") -> ZoneCondition {
        ZoneCondition(
            zoneID: "OUJ",
            chance: Chance(level: level, limitingFactor: level == .high ? nil : .activity, cloudsIncluded: cloudsIncluded),
            reason: reason ?? (level == .high ? .goodConditions : level == .moderate ? .someActivity : .lowActivity),
            activityStationID: station,
            dataTime: now.addingTimeInterval(-ageMinutes * 60))
    }

    /// Runs one cycle and returns the decided level, updating `state`.
    @discardableResult
    static func step(_ state: inout ZoneAlertState, _ condition: ZoneCondition, _ now: Date) -> ChanceLevel? {
        let (decision, next) = AlertPolicy.decide(condition: condition, state: state, now: now)
        state = next
        if let decision {
            #expect(decision.zoneID == condition.zoneID)
            #expect(decision.condition == condition)
        }
        return decision?.level
    }

    private func fresh() -> ZoneAlertState { ZoneAlertState(zoneID: "OUJ") }

    // MARK: Reference cases

    @Test func case1ModerateAlerts() {
        var state = fresh()
        #expect(Self.step(&state, Self.condition(.moderate, at: Self.at(0)), Self.at(0)) == .moderate)
        #expect(state.alertedLevels == [.moderate])
        #expect(state.alertsTonight == 1)
    }

    @Test func case2SameLevelDoesNotRepeat() {
        var state = fresh()
        Self.step(&state, Self.condition(.moderate, at: Self.at(0)), Self.at(0))
        #expect(Self.step(&state, Self.condition(.moderate, at: Self.at(5)), Self.at(5)) == nil)
    }

    @Test func case3RiseToHighAlertsAgain() {
        var state = fresh()
        Self.step(&state, Self.condition(.moderate, at: Self.at(0)), Self.at(0))
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(10)), Self.at(10)) == .high)
        #expect(state.alertedLevels == [.moderate, .high])
    }

    @Test func case4JumpToHighSendsOneAlert() {
        var state = fresh()
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(0)), Self.at(0)) == .high)
        #expect(state.alertedLevels == [.moderate, .high])
        #expect(state.alertsTonight == 1)
    }

    /// Case 4, then Moderate from 22:30 to 23:45: High re-arms at 23:30, Moderate stays alerted.
    private func afterCase5() -> ZoneAlertState {
        var state = fresh()
        Self.step(&state, Self.condition(.high, at: Self.at(0)), Self.at(0))
        for minute in stride(from: 5, through: 25, by: 5) {
            #expect(Self.step(&state, Self.condition(.high, at: Self.at(minute)), Self.at(minute)) == nil)
        }
        for minute in stride(from: 30, through: 105, by: 5) {
            #expect(Self.step(&state, Self.condition(.moderate, at: Self.at(minute)), Self.at(minute)) == nil)
            if minute < 90 {
                #expect(state.alertedLevels.contains(.high), "High still alerted at +\(minute) min")
            } else {
                #expect(!state.alertedLevels.contains(.high), "High re-armed at +\(minute) min")
            }
            #expect(state.alertedLevels.contains(.moderate))
        }
        return state
    }

    @Test func case5HighRearmsAfterSixtyMinutesBelow() {
        _ = afterCase5()
    }

    @Test func case6HighAlertsAgainAfterRearm() {
        var state = afterCase5()
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(110)), Self.at(110)) == .high)
    }

    @Test func case7ShortDropDoesNotRearm() {
        var state = fresh()
        Self.step(&state, Self.condition(.high, at: Self.at(0)), Self.at(0))
        for minute in stride(from: 30, through: 55, by: 5) {
            Self.step(&state, Self.condition(.low, at: Self.at(minute)), Self.at(minute))
        }
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(60)), Self.at(60)) == nil)
        #expect(state.belowSince.isEmpty)
    }

    @Test func case8LateDataDroppedWithoutMarking() {
        var state = fresh()
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(0), ageMinutes: 25), Self.at(0)) == nil)
        #expect(state.alertedLevels.isEmpty)
        #expect(state.alertsTonight == 0)
    }

    @Test func case9FreshDataAfterLateDataAlerts() {
        var state = fresh()
        Self.step(&state, Self.condition(.high, at: Self.at(0), ageMinutes: 25), Self.at(0))
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(5)), Self.at(5)) == .high)
    }

    @Test func lateDataBoundaryIsTwentyMinutes() {
        var state = fresh()
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(0), ageMinutes: 20), Self.at(0)) == .high)
        var other = fresh()
        #expect(Self.step(&other, Self.condition(.high, at: Self.at(0), ageMinutes: 20.1), Self.at(0)) == nil)
    }

    @Test func case10CapMarksWithoutSending() {
        var state = fresh()
        state.night = ZoneAlertState.nightKey(for: Self.at(0))
        state.alertsTonight = 3
        #expect(Self.step(&state, Self.condition(.high, at: Self.at(0)), Self.at(0)) == nil)
        #expect(state.alertedLevels == [.moderate, .high])
        #expect(state.alertsTonight == 3)
    }

    @Test func case11CapResetsWhenNightKeyChangesAtNoon() {
        var state = fresh()
        let threeAM = utc("2026-11-04T01:00:00Z")  // 03:00 Helsinki
        state.night = ZoneAlertState.nightKey(for: threeAM)
        state.alertsTonight = 3
        #expect(state.night == "2026-11-03")

        let nextEvening = utc("2026-11-04T19:00:00Z")  // 21:00 Helsinki
        #expect(Self.step(&state, Self.condition(.high, at: nextEvening), nextEvening) == .high)
        #expect(state.night == "2026-11-04")
        #expect(state.alertsTonight == 1)
    }

    @Test func case12DaylightGivesNoAlert() throws {
        let oulujarvi = try #require(AlertZones.all().first { $0.id == "OUJ" }).station
        let juneNoon = utc("2026-06-15T10:00:00Z")  // 13:00 Helsinki
        let darkness = SolarPosition.darkness(latitude: oulujarvi.latitude, longitude: oulujarvi.longitude, at: juneNoon)
        let chance = ChanceCalculator.chance(activity: .probable, darkness: darkness, moonBright: false, clouds: .clear)
        #expect(chance.level == .none)

        var state = fresh()
        let condition = ZoneCondition(zoneID: "OUJ", chance: chance, reason: .tooLight, activityStationID: "OUJ", dataTime: juneNoon)
        #expect(Self.step(&state, condition, juneNoon) == nil)
        #expect(state.alertedLevels.isEmpty)
    }

    @Test func case13OvercastGivesNoAlert() {
        let chance = ChanceCalculator.chance(activity: .probable, darkness: .dark, moonBright: false, clouds: .overcast)
        #expect(chance.level == .none)

        var state = fresh()
        let now = Self.at(60)
        let condition = ZoneCondition(zoneID: "OUJ", chance: chance, reason: .overcast, activityStationID: "OUJ", dataTime: now)
        #expect(Self.step(&state, condition, now) == nil)
    }

    @Test func case14ConditionFromAnotherStationAlerts() {
        var state = fresh()
        let condition = Self.condition(.high, at: Self.at(0), station: "RAN")
        #expect(Self.step(&state, condition, Self.at(0)) == .high)
    }

    // Case 15 (no station has a valid R → no condition, state unchanged) is in ZoneEvaluatorTests
    // and EvaluationLoopTests: without a condition the policy is not called.

    @Test func case16CloudsUnknownModerate() {
        let chance = ChanceCalculator.chance(activity: .possible, darkness: .dark, moonBright: false, clouds: .unknown)
        #expect(chance == Chance(level: .moderate, limitingFactor: .activity, cloudsIncluded: false))
        let reason = ChanceCalculator.reason(for: chance, activity: .possible, clouds: .unknown)
        #expect(reason == .someActivity)

        var state = fresh()
        let condition = ZoneCondition(zoneID: "OUJ", chance: chance, reason: reason, activityStationID: "OUJ", dataTime: Self.at(0))
        let (decision, _) = AlertPolicy.decide(condition: condition, state: state, now: Self.at(0))
        #expect(decision?.level == .moderate)
        #expect(decision.map { AlertMessage.make(for: $0, moonKeys: true) }?.bodyKey == "alert.body.someActivity.cloudsUnknown")
        Self.step(&state, condition, Self.at(0))
    }

    // MARK: Recipients

    @Test func admits() {
        #expect(AlertPolicy.admits(.moderate, .moderate))
        #expect(AlertPolicy.admits(.moderate, .high))
        #expect(!AlertPolicy.admits(.high, .moderate))
        #expect(AlertPolicy.admits(.high, .high))
        for threshold in AlertThreshold.allCases {
            #expect(!AlertPolicy.admits(threshold, .low))
            #expect(!AlertPolicy.admits(threshold, .none))
        }
    }

    // MARK: Night key

    @Test(arguments: [
        ("2026-11-03T20:00:00Z", "2026-11-03"),  // 22:00 EET
        ("2026-11-03T21:59:59Z", "2026-11-03"),  // 23:59:59
        ("2026-11-04T09:59:59Z", "2026-11-03"),  // 11:59:59 next day
        ("2026-11-04T10:00:00Z", "2026-11-04"),  // 12:00
        ("2026-06-20T08:59:59Z", "2026-06-19"),  // 11:59:59 EEST
        ("2026-06-20T09:00:00Z", "2026-06-20"),  // 12:00 EEST
        ("2026-10-25T00:30:00Z", "2026-10-24"),  // during the end of daylight saving time
    ])
    func nightKey(time: String, expected: String) {
        #expect(ZoneAlertState.nightKey(for: utc(time)) == expected)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var state = fresh()
        Self.step(&state, Self.condition(.high, at: Self.at(0)), Self.at(0))
        Self.step(&state, Self.condition(.low, at: Self.at(5)), Self.at(5))

        let decoded = try JSONDecoder().decode(ZoneAlertState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
        #expect(!decoded.belowSince.isEmpty)
    }

    // MARK: Synthetic nights

    /// One character per 5-minute cycle: `.` too light (None), `l` Low, `m` Moderate, `h` High,
    /// `x` Moderate and `y` High with 25-minute-old data, `_` no condition (no station with R).
    struct SyntheticNight: Sendable, CustomTestStringConvertible {
        var name: String
        var cycles: String
        /// (cycle index, level) of every alert the rules send.
        var expected: [(Int, ChanceLevel)]
        var start: Date = AlertPolicyTests.at(-120)  // 20:00 Helsinki
        var alertsTonightBefore: Int = 0
        var nightBefore: String?

        var testDescription: String { name }
    }

    static let syntheticNights: [SyntheticNight] = [
        SyntheticNight(name: "strong", cycles: "llmmhhhhhhhh", expected: [(2, .moderate), (4, .high)]),
        SyntheticNight(name: "moderate all night", cycles: "l" + String(repeating: "m", count: 100), expected: [(1, .moderate)]),
        SyntheticNight(name: "flickering around Moderate", cycles: "lmlmlmlmlmlmlm", expected: [(1, .moderate)]),
        SyntheticNight(name: "re-armed after 60 min below", cycles: "m" + String(repeating: "l", count: 13) + "m",
                       expected: [(0, .moderate), (14, .moderate)]),
        SyntheticNight(name: "55 min below is not enough", cycles: "m" + String(repeating: "l", count: 12) + "m",
                       expected: [(0, .moderate)]),
        SyntheticNight(name: "daylight", cycles: String(repeating: ".", count: 60), expected: []),
        SyntheticNight(name: "overcast or quiet", cycles: String(repeating: "l", count: 60) + String(repeating: ".", count: 20), expected: []),
        SyntheticNight(name: "late data then fresh", cycles: "yyyyhh", expected: [(4, .high)]),
        SyntheticNight(name: "late data only", cycles: String(repeating: "y", count: 30), expected: []),
        SyntheticNight(name: "late Moderate then fresh", cycles: "xxxm", expected: [(3, .moderate)]),
        SyntheticNight(name: "cap of three Moderate",
                       cycles: Array(repeating: "m" + String(repeating: "l", count: 13), count: 4).joined() + "m",
                       expected: [(0, .moderate), (14, .moderate), (28, .moderate)]),
        SyntheticNight(name: "cap of three High",
                       cycles: Array(repeating: "h" + String(repeating: "l", count: 13), count: 5).joined(),
                       expected: [(0, .high), (14, .high), (28, .high)]),
        SyntheticNight(name: "High re-arms while Moderate", cycles: "h" + String(repeating: "m", count: 13) + "h",
                       expected: [(0, .high), (14, .high)]),
        SyntheticNight(name: "short drop from High", cycles: "h" + String(repeating: "l", count: 6) + "h", expected: [(0, .high)]),
        SyntheticNight(name: "Moderate then High", cycles: "mmh", expected: [(0, .moderate), (2, .high)]),
        SyntheticNight(name: "High, long drop, Moderate", cycles: "h" + String(repeating: "l", count: 13) + "m",
                       expected: [(0, .high), (14, .moderate)]),
        SyntheticNight(name: "twilight then dark", cycles: "lllllmmmmmhhhhh", expected: [(5, .moderate), (10, .high)]),
        SyntheticNight(name: "data gap does not re-arm", cycles: "m" + String(repeating: "_", count: 20) + "m",
                       expected: [(0, .moderate)]),
        SyntheticNight(name: "High all night", cycles: String(repeating: "h", count: 144), expected: [(0, .high)]),
        SyntheticNight(name: "cap resets at noon", cycles: "lllh", expected: [(3, .high)],
                       start: utc("2026-11-04T09:45:00Z"), alertsTonightBefore: 3, nightBefore: "2026-11-03"),
    ]

    @Test(arguments: syntheticNights)
    func syntheticNight(_ night: SyntheticNight) {
        var state = ZoneAlertState(zoneID: "OUJ")
        if let nightBefore = night.nightBefore {
            state.night = nightBefore
            state.alertsTonight = night.alertsTonightBefore
        }
        var alerts: [(Int, ChanceLevel)] = []
        var perNight: [String: Int] = [:]

        for (index, symbol) in night.cycles.enumerated() {
            let now = night.start.addingTimeInterval(Double(index) * 300)
            let condition: ZoneCondition
            switch symbol {
            case ".": condition = Self.condition(.none, at: now, reason: .tooLight)
            case "l": condition = Self.condition(.low, at: now)
            case "m": condition = Self.condition(.moderate, at: now)
            case "h": condition = Self.condition(.high, at: now)
            case "x": condition = Self.condition(.moderate, at: now, ageMinutes: 25)
            case "y": condition = Self.condition(.high, at: now, ageMinutes: 25)
            case "_": continue
            default: Issue.record("unknown symbol \(symbol)"); continue
            }
            guard let level = Self.step(&state, condition, now) else { continue }
            alerts.append((index, level))
            // Never below the zone's chance, never in daylight or below Moderate (SC-002).
            #expect(level <= condition.chance.level)
            #expect(level >= .moderate)
            #expect(now.timeIntervalSince(condition.dataTime) <= 20 * 60)
            perNight[ZoneAlertState.nightKey(for: now), default: 0] += 1
        }

        #expect(alerts.map(\.0) == night.expected.map(\.0))
        #expect(alerts.map(\.1) == night.expected.map(\.1))
        // At most 3 per zone per night (SC-003).
        #expect(perNight.values.allSatisfy { $0 <= 3 })
    }
}
