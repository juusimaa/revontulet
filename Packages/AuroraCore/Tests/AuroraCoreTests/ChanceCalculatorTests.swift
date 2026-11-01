import Testing
@testable import AuroraCore

@Suite("Chance rules v2 (specs/003-aurora-outlook/contracts/chance-rules.md)")
struct ChanceCalculatorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let number: Int
        let activity: ActivityLevel
        let darkness: Darkness
        var moonBright = false
        let clouds: CloudCondition
        let level: ChanceLevel
        let limiting: LimitingFactor?
        let reason: ChanceReason

        var testDescription: String { "case \(number)" }
    }

    static let referenceCases: [Case] = [
        Case(number: 1, activity: .probable, darkness: .dark, clouds: .clear, level: .high, limiting: nil, reason: .goodConditions),
        Case(number: 2, activity: .probable, darkness: .tooLight, clouds: .clear, level: .none, limiting: .light, reason: .tooLight),
        Case(number: 3, activity: .probable, darkness: .dark, clouds: .overcast, level: .none, limiting: .clouds, reason: .overcast),
        Case(number: 4, activity: .probable, darkness: .twilight, clouds: .clear, level: .moderate, limiting: .twilight, reason: .twilight),
        Case(number: 5, activity: .probable, darkness: .dark, clouds: .partly, level: .moderate, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 6, activity: .probable, darkness: .twilight, clouds: .partly, level: .low, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 7, activity: .possible, darkness: .dark, clouds: .clear, level: .moderate, limiting: .activity, reason: .someActivity),
        Case(number: 8, activity: .possible, darkness: .twilight, clouds: .partly, level: .none, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 9, activity: .unlikely, darkness: .dark, clouds: .clear, level: .low, limiting: .activity, reason: .lowActivity),
        Case(number: 10, activity: .unlikely, darkness: .twilight, clouds: .clear, level: .none, limiting: .activity, reason: .lowActivity),
        Case(number: 11, activity: .probable, darkness: .dark, clouds: .unknown, level: .high, limiting: nil, reason: .goodConditions),
        Case(number: 12, activity: .unlikely, darkness: .tooLight, clouds: .overcast, level: .none, limiting: .light, reason: .tooLight),
        Case(number: 13, activity: .probable, darkness: .dark, moonBright: true, clouds: .clear, level: .moderate, limiting: .moon, reason: .brightMoon),
        Case(number: 14, activity: .possible, darkness: .dark, moonBright: true, clouds: .clear, level: .low, limiting: .moon, reason: .brightMoon),
        Case(number: 15, activity: .unlikely, darkness: .dark, moonBright: true, clouds: .clear, level: .none, limiting: .activity, reason: .lowActivity),
        Case(number: 16, activity: .probable, darkness: .twilight, moonBright: true, clouds: .clear, level: .moderate, limiting: .twilight, reason: .twilight),
        Case(number: 17, activity: .probable, darkness: .dark, moonBright: true, clouds: .partly, level: .low, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 18, activity: .probable, darkness: .twilight, moonBright: true, clouds: .partly, level: .low, limiting: .clouds, reason: .partlyCloudy),
        Case(number: 19, activity: .probable, darkness: .tooLight, moonBright: true, clouds: .clear, level: .none, limiting: .light, reason: .tooLight),
        Case(number: 20, activity: .probable, darkness: .dark, moonBright: true, clouds: .overcast, level: .none, limiting: .clouds, reason: .overcast),
        Case(number: 21, activity: .probable, darkness: .dark, moonBright: true, clouds: .unknown, level: .moderate, limiting: .moon, reason: .brightMoon),
        Case(number: 22, activity: .possible, darkness: .twilight, moonBright: true, clouds: .clear, level: .low, limiting: .twilight, reason: .twilight),
        Case(number: 23, activity: .unlikely, darkness: .dark, clouds: .partly, level: .none, limiting: .activity, reason: .lowActivity),
        Case(number: 24, activity: .unlikely, darkness: .twilight, moonBright: true, clouds: .partly, level: .none, limiting: .activity, reason: .lowActivity),
    ]

    @Test(arguments: referenceCases)
    func referenceCase(_ c: Case) {
        let chance = ChanceCalculator.chance(
            activity: c.activity, darkness: c.darkness, moonBright: c.moonBright, clouds: c.clouds)

        #expect(chance.level == c.level)
        #expect(chance.limitingFactor == c.limiting)
        #expect(chance.cloudsIncluded == (c.clouds != .unknown))
        #expect(ChanceCalculator.reason(for: chance, activity: c.activity, clouds: c.clouds) == c.reason)
    }

    @Test func everyCombinationGivesALevelNoHigherThanActivityAllows() {
        for activity in ActivityLevel.allCases {
            for darkness in Darkness.allCases {
                for moonBright in [false, true] {
                    for clouds in CloudCondition.allCases {
                        let chance = ChanceCalculator.chance(
                            activity: activity, darkness: darkness, moonBright: moonBright, clouds: clouds)
                        #expect(chance.level <= ChanceCalculator.startingLevel(activity))
                        #expect(chance.limitingFactor != nil || chance.level == .high)
                    }
                }
            }
        }
    }

    /// Twilight and a bright moon together lower the level by one step, never two (step 4).
    @Test func twilightAndBrightMoonLowerByAtMostOneStep() {
        for activity in ActivityLevel.allCases {
            for clouds in CloudCondition.allCases {
                let twilight = ChanceCalculator.chance(activity: activity, darkness: .twilight, moonBright: false, clouds: clouds)
                let both = ChanceCalculator.chance(activity: activity, darkness: .twilight, moonBright: true, clouds: clouds)
                let moonOnly = ChanceCalculator.chance(activity: activity, darkness: .dark, moonBright: true, clouds: clouds)
                let neither = ChanceCalculator.chance(activity: activity, darkness: .dark, moonBright: false, clouds: clouds)

                #expect(both == twilight, "\(activity) \(clouds)")
                #expect(moonOnly.level == twilight.level, "\(activity) \(clouds)")
                #expect(neither.level.rawValue - both.level.rawValue <= 1, "\(activity) \(clouds)")
            }
        }
    }

    @Test(arguments: [
        (Optional(0), CloudCondition.clear), (3, .clear),
        (4, .partly), (6, .partly),
        (7, .overcast), (8, .overcast),
        (9, .unknown), (nil, .unknown),
    ])
    func cloudMapping(octas: Int?, expected: CloudCondition) {
        #expect(ChanceCalculator.cloudCondition(octas: octas) == expected)
    }

    @Test func reasonKeys() {
        #expect(ChanceReason.tooLight.key == "reason.tooLight")
        #expect(ChanceReason.goodConditions.key == "reason.goodConditions")
        #expect(ChanceReason.brightMoon.key == "reason.brightMoon")
        #expect(Set(ChanceReason.allCases.map(\.key)).count == ChanceReason.allCases.count)
    }
}
